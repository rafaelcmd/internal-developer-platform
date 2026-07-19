package main

import (
	"context"
	"errors"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/aws/aws-sdk-go-v2/service/ssm"
	"go.opentelemetry.io/contrib/instrumentation/github.com/aws/aws-sdk-go-v2/otelaws"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/metric"
	"go.opentelemetry.io/otel/trace"

	"github.com/rafaelcmd/internal-developer-platform/resource-provisioner-service/internal/telemetry"
)

const serviceName = "resource-provisioner-consumer"

var errEmptyQueueURL = errors.New("SQS queue URL is empty")

func main() {
	// Root context cancels on SIGINT/SIGTERM so the poll loop drains and the
	// telemetry batch exporters flush before exit.
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	shutdownTelemetry, err := telemetry.Setup(ctx, telemetry.Config{
		ServiceName: serviceName,
		Version:     os.Getenv("SERVICE_VERSION"),
		Environment: envOrDefault("ENVIRONMENT", "dev"),
	})
	if err != nil {
		log.Fatalf("Unable to set up telemetry, %v", err)
	}
	defer func() {
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := shutdownTelemetry(shutdownCtx); err != nil {
			log.Printf("Telemetry shutdown error: %v", err)
		}
	}()

	cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion("us-east-1"))
	if err != nil {
		log.Fatalf("Unable to load AWS config, %v", err)
	}
	// Instrument every AWS SDK call with an OTel span (replaces xray.Client).
	otelaws.AppendMiddlewares(&cfg.APIOptions)

	sqsClient := sqs.NewFromConfig(cfg)
	ssmClient := ssm.NewFromConfig(cfg)

	tracer := otel.Tracer(serviceName)
	meter := otel.Meter(serviceName)
	messagesReceived, _ := meter.Int64Counter("provisioner.messages.received",
		metric.WithDescription("SQS messages received from the provisioning queue"))
	messagesProcessed, _ := meter.Int64Counter("provisioner.messages.processed",
		metric.WithDescription("SQS messages processed and deleted successfully"))
	messagesFailed, _ := meter.Int64Counter("provisioner.messages.failed",
		metric.WithDescription("SQS messages that failed to delete after processing"))

	queueURL, err := getQueueURL(ctx, tracer, ssmClient)
	if err != nil {
		log.Fatalf("Unable to get SQS queue URL from Parameter Store, %v", err)
	}

	log.Println("Polling messages from SQS queue:", queueURL)

	for ctx.Err() == nil {
		pollCtx, pollSpan := tracer.Start(ctx, "PollSQSMessages")

		output, err := sqsClient.ReceiveMessage(pollCtx, &sqs.ReceiveMessageInput{
			QueueUrl:            aws.String(queueURL),
			MaxNumberOfMessages: 5,
			WaitTimeSeconds:     10,
		})
		if err != nil {
			pollSpan.RecordError(err)
			pollSpan.End()
			// A cancelled context is a clean shutdown, not a poll failure.
			if ctx.Err() != nil {
				break
			}
			log.Printf("Failed to receive messages, %v", err)
			continue
		}
		messagesReceived.Add(pollCtx, int64(len(output.Messages)))

		for _, message := range output.Messages {
			processCtx, span := tracer.Start(pollCtx, "ProcessMessage")
			log.Printf("Received message: %s", aws.ToString(message.Body))

			// Save message data in RDS

			// Delete the message after processing
			_, err := sqsClient.DeleteMessage(processCtx, &sqs.DeleteMessageInput{
				QueueUrl:      aws.String(queueURL),
				ReceiptHandle: message.ReceiptHandle,
			})
			if err != nil {
				messagesFailed.Add(processCtx, 1)
				span.RecordError(err)
				log.Printf("Failed to delete message, %v", err)
			} else {
				messagesProcessed.Add(processCtx, 1)
				log.Println("Message deleted successfully")
			}
			span.End()
		}

		pollSpan.End()
	}
}

// getQueueURL reads the provisioning queue URL from Parameter Store within its
// own span.
func getQueueURL(ctx context.Context, tracer trace.Tracer, ssmClient *ssm.Client) (string, error) {
	ctx, span := tracer.Start(ctx, "GetSQSQueueURL")
	defer span.End()

	param, err := ssmClient.GetParameter(ctx, &ssm.GetParameterInput{
		Name: aws.String("/INTERNAL_DEVELOPER_PLATFORM/SQS_QUEUE_URL"),
	})
	if err != nil {
		span.RecordError(err)
		return "", err
	}

	queueURL := aws.ToString(param.Parameter.Value)
	if queueURL == "" {
		return "", errEmptyQueueURL
	}
	return queueURL, nil
}

func envOrDefault(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
