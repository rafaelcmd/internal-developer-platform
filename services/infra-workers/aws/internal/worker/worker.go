// Package worker is the AWS infra worker's consume loop: it receives
// ProvisionInfra tasks from SQS, handles each one, reports the outcome to Step
// Functions with the task token, and acknowledges the message.
//
// Handling a task is logging it. No Terraform runs yet, and the result reported
// to Step Functions says so explicitly rather than claiming resources exist.
package worker

import (
	"context"
	"encoding/json"
	"errors"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/sfn"
	sfntypes "github.com/aws/aws-sdk-go-v2/service/sfn/types"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"

	"github.com/rafaelcmd/internal-developer-platform/infra-worker-aws/internal/logger"
	"github.com/rafaelcmd/internal-developer-platform/infra-worker-aws/internal/task"
)

// SQSClient is the part of the SQS API the loop uses. *sqs.Client satisfies it.
type SQSClient interface {
	ReceiveMessage(context.Context, *sqs.ReceiveMessageInput, ...func(*sqs.Options)) (*sqs.ReceiveMessageOutput, error)
	DeleteMessage(context.Context, *sqs.DeleteMessageInput, ...func(*sqs.Options)) (*sqs.DeleteMessageOutput, error)
}

// SFNClient is the part of the Step Functions API the loop uses.
// *sfn.Client satisfies it.
type SFNClient interface {
	SendTaskSuccess(context.Context, *sfn.SendTaskSuccessInput, ...func(*sfn.Options)) (*sfn.SendTaskSuccessOutput, error)
}

// Result is what the worker reports to Step Functions. The state machine
// stores it at $.infrastructure.
type Result struct {
	// Provisioned is false because nothing is created yet. A caller reading the
	// execution output must not mistake a logged task for real infrastructure.
	Provisioned bool `json:"Provisioned"`

	// Mode names how the task was handled.
	Mode string `json:"Mode"`

	ResourceCount int `json:"ResourceCount"`
}

// Worker consumes one task queue.
type Worker struct {
	SQS      SQSClient
	SFN      SFNClient
	QueueURL string
	Tracer   trace.Tracer
	Log      logger.Logger
}

// Run long-polls the queue until ctx is cancelled.
func (w Worker) Run(ctx context.Context) error {
	w.Log.WithContext(ctx).Info("polling for tasks", logger.F("queue_url", w.QueueURL))

	for ctx.Err() == nil {
		output, err := w.SQS.ReceiveMessage(ctx, &sqs.ReceiveMessageInput{
			QueueUrl:            aws.String(w.QueueURL),
			MaxNumberOfMessages: 10,
			WaitTimeSeconds:     20,
		})
		if err != nil {
			// A cancelled context is a clean shutdown, not a poll failure.
			if ctx.Err() != nil {
				break
			}
			w.Log.WithContext(ctx).Error("failed to receive tasks", logger.F("error", err.Error()))
			continue
		}

		for _, message := range output.Messages {
			if !w.process(ctx, []byte(aws.ToString(message.Body))) {
				continue
			}

			if _, err := w.SQS.DeleteMessage(ctx, &sqs.DeleteMessageInput{
				QueueUrl:      aws.String(w.QueueURL),
				ReceiptHandle: message.ReceiptHandle,
			}); err != nil {
				w.Log.WithContext(ctx).Error("failed to delete task message", logger.F("error", err.Error()))
			}
		}
	}

	w.Log.WithContext(ctx).Info("shutting down")
	return nil
}

// process handles one message and reports whether it may be deleted. A message
// that is not deleted becomes visible again after the visibility timeout, and
// the redrive policy moves it to the dead-letter queue if that keeps happening.
func (w Worker) process(ctx context.Context, body []byte) bool {
	ctx, span := w.Tracer.Start(ctx, "ProcessProvisionInfraTask")
	defer span.End()

	message, err := Handle(ctx, w.Log, body)
	if err != nil {
		span.SetStatus(codes.Error, "task message could not be understood")
		return false
	}

	input := message.Input
	span.SetAttributes(
		attribute.String("provision.request_id", input.RequestID),
		attribute.String("provision.application", input.ApplicationName),
	)
	log := w.Log.WithContext(ctx).WithFields(logger.Fields{
		"request_id":       input.RequestID,
		"application_name": input.ApplicationName,
	})

	owned, _ := input.Partition()
	output, err := json.Marshal(Result{Provisioned: false, Mode: "log-only", ResourceCount: len(owned)})
	if err != nil {
		span.RecordError(err)
		return false
	}

	_, err = w.SFN.SendTaskSuccess(ctx, &sfn.SendTaskSuccessInput{
		TaskToken: aws.String(message.TaskToken),
		Output:    aws.String(string(output)),
	})
	if err != nil {
		span.RecordError(err)

		// The execution behind this token is gone or has already moved on, so a
		// redelivery could only fail the same way. Deleting the message stops
		// it cycling into the dead-letter queue.
		if tokenIsDead(err) {
			log.Warn("task token no longer accepted, dropping task", logger.F("error", err.Error()))
			return true
		}

		span.SetStatus(codes.Error, "could not report task outcome")
		log.Error("failed to report task success, leaving task for redelivery", logger.F("error", err.Error()))
		return false
	}

	log.Info("task success reported to step functions", logger.F("result", string(output)))
	return true
}

func tokenIsDead(err error) bool {
	var timedOut *sfntypes.TaskTimedOut
	var notFound *sfntypes.TaskDoesNotExist
	var invalid *sfntypes.InvalidToken
	return errors.As(err, &timedOut) || errors.As(err, &notFound) || errors.As(err, &invalid)
}

// Handle parses a ProvisionInfra task and logs it. It returns an error only when
// the message cannot be understood, which is the one case where it must not be
// acknowledged.
func Handle(ctx context.Context, log logger.Logger, body []byte) (task.Message, error) {
	message, err := task.Parse(body)
	if err != nil {
		log.WithContext(ctx).Error("could not understand task message",
			logger.F("error", err.Error()),
			logger.F("body", string(body)),
		)
		return task.Message{}, err
	}

	input := message.Input
	log = log.WithContext(ctx).WithFields(logger.Fields{
		"request_id":       input.RequestID,
		"application_name": input.ApplicationName,
	})

	owned, foreign := input.Partition()

	for _, resource := range owned {
		log.Info("resource to provision",
			logger.F("resource_name", resource.Name),
			logger.F("resource_type", resource.ResourceType),
			logger.F("specification", resource.Specification),
		)
	}

	// The control plane routes resources by provider, so a foreign resource here
	// means that routing is wrong. It is reported and never provisioned.
	for _, resource := range foreign {
		log.Warn("resource belongs to another provider",
			logger.F("resource_name", resource.Name),
			logger.F("resource_type", resource.ResourceType),
			logger.F("cloud_provider", resource.CloudProvider),
		)
	}

	log.Info("provision infra task received",
		logger.F("resource_count", len(owned)),
		logger.F("foreign_resource_count", len(foreign)),
	)

	return message, nil
}
