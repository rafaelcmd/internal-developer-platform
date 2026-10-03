// Command worker is the AWS infra worker: it consumes ProvisionInfra tasks from
// the scaffold state machine and provisions the AWS resources they name.
//
// It does not provision anything yet. Each task is logged and acknowledged, and
// no result is reported to Step Functions, so the ProvisionInfra state stays a
// Fail state until the worker calls SendTaskSuccess and SendTaskFailure.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sqs"

	"github.com/rafaelcmd/internal-developer-platform/infra-worker-aws/internal/task"
)

func main() {
	file := flag.String("file", "", "log a single task message read from this file instead of polling SQS")
	flag.Parse()

	log := slog.New(slog.NewJSONHandler(os.Stdout, nil)).With("provider", task.Provider)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	if err := run(ctx, log, *file); err != nil {
		log.Error("worker stopped", "error", err.Error())
		os.Exit(1)
	}
}

func run(ctx context.Context, log *slog.Logger, file string) error {
	if file != "" {
		body, err := os.ReadFile(file)
		if err != nil {
			return err
		}
		return handle(log, body)
	}

	queueURL := os.Getenv("TASK_QUEUE_URL")
	if queueURL == "" {
		return errors.New("TASK_QUEUE_URL is not set; pass -file to log a message without SQS")
	}

	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return fmt.Errorf("load AWS config: %w", err)
	}

	return poll(ctx, log, sqs.NewFromConfig(cfg), queueURL)
}

func poll(ctx context.Context, log *slog.Logger, client *sqs.Client, queueURL string) error {
	log.Info("polling for tasks", "queue_url", queueURL)

	for ctx.Err() == nil {
		output, err := client.ReceiveMessage(ctx, &sqs.ReceiveMessageInput{
			QueueUrl:            aws.String(queueURL),
			MaxNumberOfMessages: 10,
			WaitTimeSeconds:     20,
		})
		if err != nil {
			if ctx.Err() != nil {
				break
			}
			log.Error("receive failed", "error", err.Error())
			continue
		}

		for _, message := range output.Messages {
			// A message that cannot be parsed stays on the queue, so the redrive
			// policy moves it to the dead-letter queue instead of it being lost.
			if err := handle(log, []byte(aws.ToString(message.Body))); err != nil {
				continue
			}

			if _, err := client.DeleteMessage(ctx, &sqs.DeleteMessageInput{
				QueueUrl:      aws.String(queueURL),
				ReceiptHandle: message.ReceiptHandle,
			}); err != nil {
				log.Error("delete failed", "error", err.Error())
			}
		}
	}

	log.Info("shutting down")
	return nil
}

// handle logs a ProvisionInfra task. It returns an error only when the message
// cannot be understood; that is the one case where it must not be acknowledged.
func handle(log *slog.Logger, body []byte) error {
	message, err := task.Parse(body)
	if err != nil {
		log.Error("could not understand task message", "error", err.Error(), "body", string(body))
		return err
	}

	input := message.Input
	log = log.With("request_id", input.RequestID, "application_name", input.ApplicationName)

	owned, foreign := input.Partition()

	for _, resource := range owned {
		log.Info("resource to provision",
			"resource_name", resource.Name,
			"resource_type", resource.ResourceType,
			"specification", resource.Specification,
		)
	}

	// The control plane routes resources by provider, so a foreign resource here
	// means that routing is wrong. It is reported and never provisioned.
	for _, resource := range foreign {
		log.Warn("resource belongs to another provider",
			"resource_name", resource.Name,
			"resource_type", resource.ResourceType,
			"cloud_provider", resource.CloudProvider,
		)
	}

	log.Info("provision infra task received",
		"resource_count", len(owned),
		"foreign_resource_count", len(foreign),
	)

	return nil
}
