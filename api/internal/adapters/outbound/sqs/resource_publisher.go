package sqs

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/sqs"

	"github.com/rafaelcmd/internal-developer-platform/api/internal/domain/errors"
	"github.com/rafaelcmd/internal-developer-platform/api/internal/domain/model"
	"github.com/rafaelcmd/internal-developer-platform/api/internal/domain/ports/outbound"
)

// ResourcePublisher publishes resource provisioning requests to SQS.
type ResourcePublisher struct {
	client   *sqs.Client
	queueURL string
}

// Ensure ResourcePublisher implements the ResourcePublisher interface.
var _ outbound.ResourcePublisher = (*ResourcePublisher)(nil)

// NewResourcePublisher creates a new ResourcePublisher.
func NewResourcePublisher(client *sqs.Client, queueURL string) *ResourcePublisher {
	return &ResourcePublisher{
		client:   client,
		queueURL: queueURL,
	}
}

// Publish sends a resource provisioning request to the SQS queue.
func (p *ResourcePublisher) Publish(ctx context.Context, resource model.Resource) error {
	body, err := json.Marshal(resource)
	if err != nil {
		return errors.NewDomainError(
			errors.ErrCodeQueueError,
			"failed to serialize resource for publishing",
			err,
		)
	}

	_, err = p.client.SendMessage(ctx, &sqs.SendMessageInput{
		MessageBody: aws.String(string(body)),
		QueueUrl:    aws.String(p.queueURL),
	})
	if err != nil {
		return errors.NewDomainError(
			errors.ErrCodeQueueError,
			fmt.Sprintf("failed to publish resource %s to queue", resource.ID),
			err,
		)
	}

	return nil
}
