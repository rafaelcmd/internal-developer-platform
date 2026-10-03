// Command worker is the AWS infra worker: it consumes ProvisionInfra tasks from
// the scaffold state machine and provisions the AWS resources they name.
//
// It does not provision anything yet. Each task is logged, reported to Step
// Functions as succeeded with Provisioned=false, and acknowledged.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sfn"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/sirupsen/logrus"
	"go.opentelemetry.io/contrib/instrumentation/github.com/aws/aws-sdk-go-v2/otelaws"
	"go.opentelemetry.io/otel"

	"github.com/rafaelcmd/internal-developer-platform/infra-worker-aws/internal/logger"
	"github.com/rafaelcmd/internal-developer-platform/infra-worker-aws/internal/task"
	"github.com/rafaelcmd/internal-developer-platform/infra-worker-aws/internal/telemetry"
	"github.com/rafaelcmd/internal-developer-platform/infra-worker-aws/internal/worker"
)

const serviceName = "infra-worker-aws"

func main() {
	file := flag.String("file", "", "log a single task message read from this file instead of polling SQS")
	flag.Parse()

	// Cancels on SIGINT/SIGTERM so the loop stops polling and the telemetry
	// batch exporters flush before exit.
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	shutdownTelemetry, logHook, err := telemetry.Setup(ctx, telemetry.Config{
		ServiceName: serviceName,
		Version:     os.Getenv("SERVICE_VERSION"),
		Environment: envOrDefault("ENVIRONMENT", "dev"),
	})

	// Built after Setup so the OTLP bridge hook, which is what carries these
	// logs to the Collector and on to Datadog, is attached at construction.
	logCfg := logger.DefaultConfig()
	if logHook != nil {
		logCfg.Hooks = []logrus.Hook{logHook}
	}
	log := logger.New(logCfg).WithField("provider", task.Provider)

	if err != nil {
		log.WithContext(ctx).Error("unable to set up telemetry", logger.F("error", err.Error()))
		os.Exit(1)
	}
	defer func() {
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := shutdownTelemetry(shutdownCtx); err != nil {
			log.WithContext(shutdownCtx).Error("telemetry shutdown error", logger.F("error", err.Error()))
		}
	}()

	if err := run(ctx, log, *file); err != nil {
		log.WithContext(ctx).Error("worker stopped", logger.F("error", err.Error()))
		// os.Exit skips deferred calls, so flush before leaving.
		stop()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		_ = shutdownTelemetry(shutdownCtx)
		cancel()
		os.Exit(1)
	}
}

func run(ctx context.Context, log logger.Logger, file string) error {
	if file != "" {
		body, err := os.ReadFile(file)
		if err != nil {
			return err
		}
		_, err = worker.Handle(ctx, log, body)
		return err
	}

	queueName := os.Getenv("TASK_QUEUE_NAME")
	if queueName == "" {
		return fmt.Errorf("TASK_QUEUE_NAME is not set; pass -file to log a message without SQS")
	}

	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return fmt.Errorf("load AWS config: %w", err)
	}
	otelaws.AppendMiddlewares(&cfg.APIOptions)

	sqsClient := sqs.NewFromConfig(cfg)

	// Configured by name so no account id lands in the manifest.
	queue, err := sqsClient.GetQueueUrl(ctx, &sqs.GetQueueUrlInput{QueueName: aws.String(queueName)})
	if err != nil {
		return fmt.Errorf("resolve queue %s: %w", queueName, err)
	}

	return worker.Worker{
		SQS:      sqsClient,
		SFN:      sfn.NewFromConfig(cfg),
		QueueURL: aws.ToString(queue.QueueUrl),
		Tracer:   otel.Tracer(serviceName),
		Log:      log,
	}.Run(ctx)
}

func envOrDefault(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
