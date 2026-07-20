package consumer

import (
	"context"
	"log"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"go.opentelemetry.io/otel/trace"
)

// RunSQS long-polls the queue and deletes each message after processing
// (at-least-once) until the context is cancelled.
func RunSQS(ctx context.Context, client *sqs.Client, queueURL string, tracer trace.Tracer, metrics Metrics) error {
	log.Println("Polling messages from SQS queue:", queueURL)

	for ctx.Err() == nil {
		pollCtx, pollSpan := tracer.Start(ctx, "PollSQSMessages")

		output, err := client.ReceiveMessage(pollCtx, &sqs.ReceiveMessageInput{
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
		metrics.Received.Add(pollCtx, int64(len(output.Messages)))

		for _, message := range output.Messages {
			processCtx, span := tracer.Start(pollCtx, "ProcessMessage")
			log.Printf("Received message: %s", aws.ToString(message.Body))

			// Save message data in RDS

			// Delete the message after processing.
			_, err := client.DeleteMessage(processCtx, &sqs.DeleteMessageInput{
				QueueUrl:      aws.String(queueURL),
				ReceiptHandle: message.ReceiptHandle,
			})
			if err != nil {
				metrics.Failed.Add(processCtx, 1)
				span.RecordError(err)
				log.Printf("Failed to delete message, %v", err)
			} else {
				metrics.Processed.Add(processCtx, 1)
				log.Println("Message deleted successfully")
			}
			span.End()
		}

		pollSpan.End()
	}

	return ctx.Err()
}
