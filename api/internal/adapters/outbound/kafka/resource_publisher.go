// Package kafka provides a Kafka-backed implementation of the ResourcePublisher
// port, used in local development in place of SQS so the full
// API -> queue -> provisioner flow runs offline without AWS.
package kafka

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/segmentio/kafka-go"

	"github.com/rafaelcmd/internal-developer-platform/api/internal/domain/errors"
	"github.com/rafaelcmd/internal-developer-platform/api/internal/domain/model"
	"github.com/rafaelcmd/internal-developer-platform/api/internal/domain/ports/outbound"
)

// ResourcePublisher publishes resource provisioning requests to a Kafka topic.
type ResourcePublisher struct {
	writer *kafka.Writer
}

// Ensure ResourcePublisher implements the ResourcePublisher interface.
var _ outbound.ResourcePublisher = (*ResourcePublisher)(nil)

// NewResourcePublisher creates a publisher writing to the given topic on the
// given brokers. AllowAutoTopicCreation makes the topic appear on first write,
// which suits the local Kafka stack.
func NewResourcePublisher(brokers []string, topic string) *ResourcePublisher {
	return &ResourcePublisher{
		writer: &kafka.Writer{
			Addr:                   kafka.TCP(brokers...),
			Topic:                  topic,
			Balancer:               &kafka.Hash{},
			AllowAutoTopicCreation: true,
		},
	}
}

// Publish serializes the resource and writes it to Kafka, keyed by resource ID
// so all messages for a resource land on the same partition (ordering).
func (p *ResourcePublisher) Publish(ctx context.Context, resource model.Resource) error {
	body, err := json.Marshal(resource)
	if err != nil {
		return errors.NewDomainError(
			errors.ErrCodeQueueError,
			"failed to serialize resource for publishing",
			err,
		)
	}

	err = p.writer.WriteMessages(ctx, kafka.Message{
		Key:   []byte(resource.ID),
		Value: body,
	})
	if err != nil {
		return errors.NewDomainError(
			errors.ErrCodeQueueError,
			fmt.Sprintf("failed to publish resource %s to kafka", resource.ID),
			err,
		)
	}

	return nil
}

// Close flushes and releases the underlying Kafka writer.
func (p *ResourcePublisher) Close() error {
	return p.writer.Close()
}
