package consumer

import (
	"context"
	"log"

	"github.com/segmentio/kafka-go"
	"go.opentelemetry.io/otel/trace"
)

// KafkaConfig configures the Kafka consumer.
type KafkaConfig struct {
	Brokers []string
	Topic   string
	GroupID string
}

// RunKafka consumes the provisioning topic with a consumer group until the
// context is cancelled. Offsets are committed only after a message is processed
// (at-least-once), mirroring the SQS delete-after-process semantics.
func RunKafka(ctx context.Context, cfg KafkaConfig, tracer trace.Tracer, metrics Metrics) error {
	reader := kafka.NewReader(kafka.ReaderConfig{
		Brokers: cfg.Brokers,
		Topic:   cfg.Topic,
		GroupID: cfg.GroupID,
	})
	defer reader.Close()

	log.Printf("Consuming messages from Kafka topic %q (group %q)", cfg.Topic, cfg.GroupID)

	for ctx.Err() == nil {
		message, err := reader.FetchMessage(ctx)
		if err != nil {
			// A cancelled context is a clean shutdown, not a fetch failure.
			if ctx.Err() != nil {
				break
			}
			log.Printf("Failed to fetch message, %v", err)
			continue
		}
		metrics.Received.Add(ctx, 1)

		processCtx, span := tracer.Start(ctx, "ProcessMessage")
		log.Printf("Received message: %s", string(message.Value))

		// Save message data in RDS

		// Commit the offset after processing.
		if err := reader.CommitMessages(processCtx, message); err != nil {
			metrics.Failed.Add(processCtx, 1)
			span.RecordError(err)
			log.Printf("Failed to commit message, %v", err)
		} else {
			metrics.Processed.Add(processCtx, 1)
			log.Println("Message committed successfully")
		}
		span.End()
	}

	return ctx.Err()
}
