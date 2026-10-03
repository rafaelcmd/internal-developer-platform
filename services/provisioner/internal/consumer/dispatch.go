package consumer

import (
	"context"

	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"

	"github.com/rafaelcmd/internal-developer-platform/resource-provisioner-service/internal/logger"
	"github.com/rafaelcmd/internal-developer-platform/resource-provisioner-service/internal/provision"
)

// Dispatch performs the control-plane step: it decodes the request published by
// the API, separates it into the work owned by each downstream worker, and
// starts the scaffold state machine that carries it out.
//
// It is shared by the SQS and Kafka consume loops so that local development
// exercises the same code path as the deployed environments. starter is nil on
// the Kafka path, which never touches AWS; the split is then logged and nothing
// is started.
//
// The return value reports whether the message has been handled and may be
// acknowledged: false when it could not be decoded, or when the execution could
// not be started and a redelivery should try again.
func Dispatch(ctx context.Context, body []byte, starter ExecutionStarter, tracer trace.Tracer, log logger.Logger) bool {
	request, err := provision.Parse(body)
	if err != nil {
		// The API validates this shape before publishing, so a failure here
		// indicates a message produced outside the API or divergence between the
		// two contract definitions. Neither is resolved by a retry.
		//
		// Returning false leaves the message on the queue. It used to be
		// acknowledged here, because the queue had no dead-letter queue and the
		// alternative was redelivering forever; the queue has one now, so the
		// redrive policy takes the message out of circulation after
		// maxReceiveCount and puts it somewhere it can be read.
		log.WithContext(ctx).Error("could not understand provision request",
			logger.F("error", err.Error()),
			logger.F("body", string(body)),
		)
		return false
	}

	scaffold, infra := request.Split()

	_, span := tracer.Start(ctx, "SplitProvisionRequest")
	defer span.End()

	span.SetAttributes(
		attribute.String("provision.request_id", request.RequestID),
		attribute.String("provision.application", scaffold.ApplicationName),
		attribute.String("provision.template", scaffold.Template),
		attribute.Int("provision.resource_count", len(infra.Resources)),
	)

	// One entry per half, so the logs show the request as it will execute: a
	// scaffold branch and an infrastructure branch sharing a request id and a
	// trace.
	log.WithContext(ctx).Info("scaffold work",
		logger.F("request_id", scaffold.RequestID),
		logger.F("application_name", scaffold.ApplicationName),
		logger.F("template", scaffold.Template),
		logger.F("owner", scaffold.Owner),
	)

	if infra.HasWork() {
		log.WithContext(ctx).Info("infrastructure work",
			logger.F("request_id", infra.RequestID),
			logger.F("application_name", infra.ApplicationName),
			logger.F("resource_count", len(infra.Resources)),
			logger.F("resource_types", infra.ResourceTypes()),
		)
	} else {
		// Logged explicitly so that a request with no resources is
		// distinguishable from resources lost during the split.
		log.WithContext(ctx).Info("no infrastructure work",
			logger.F("request_id", infra.RequestID),
			logger.F("application_name", infra.ApplicationName),
		)
	}

	if starter == nil {
		log.WithContext(ctx).Info("no state machine configured, execution not started",
			logger.F("request_id", request.RequestID),
		)
		return true
	}

	return startExecution(ctx, body, request.RequestID, starter, tracer, log)
}

// startExecution hands the request to the state machine. The execution input is
// the message body unchanged: the machine reads the same snake_case fields the
// API publishes, so there is nothing to translate.
func startExecution(ctx context.Context, body []byte, requestID string, starter ExecutionStarter, tracer trace.Tracer, log logger.Logger) bool {
	ctx, span := tracer.Start(ctx, "StartScaffoldExecution")
	defer span.End()

	span.SetAttributes(attribute.String("provision.request_id", requestID))

	started, err := starter.Start(ctx, requestID, body)
	if err != nil {
		// Left unacknowledged: a throttle or a network fault clears on
		// redelivery, and the deterministic execution name makes the retry
		// safe even if this call reached Step Functions after all.
		span.RecordError(err)
		span.SetStatus(codes.Error, "start execution failed")
		log.WithContext(ctx).Error("could not start scaffold execution",
			logger.F("request_id", requestID),
			logger.F("error", err.Error()),
		)
		return false
	}

	if started.AlreadyStarted {
		log.WithContext(ctx).Info("scaffold execution already started by an earlier delivery",
			logger.F("request_id", requestID),
		)
		return true
	}

	span.SetAttributes(attribute.String("provision.execution_arn", started.ExecutionArn))
	log.WithContext(ctx).Info("scaffold execution started",
		logger.F("request_id", requestID),
		logger.F("execution_arn", started.ExecutionArn),
	)
	return true
}
