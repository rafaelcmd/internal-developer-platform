package consumer

import (
	"context"

	sqstypes "github.com/aws/aws-sdk-go-v2/service/sqs/types"
	"github.com/segmentio/kafka-go"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"
)

// The API injects W3C trace context (traceparent/tracestate/baggage) into each
// message when it publishes, so the span that processes a message here becomes a
// child of the API's producer span and the two services' logs share one
// trace_id. These carriers adapt the transport's metadata to OTel's
// TextMapCarrier so the global propagator can read it back out.

// extractKafka returns a context carrying the trace context found in a Kafka
// message's headers. Missing/empty headers yield the parent context unchanged.
func extractKafka(ctx context.Context, headers []kafka.Header) context.Context {
	return otel.GetTextMapPropagator().Extract(ctx, kafkaHeaderCarrier(headers))
}

// extractSQS returns a context carrying the trace context found in an SQS
// message's attributes. Missing/empty attributes yield the parent context
// unchanged.
func extractSQS(ctx context.Context, attrs map[string]sqstypes.MessageAttributeValue) context.Context {
	return otel.GetTextMapPropagator().Extract(ctx, sqsAttributeCarrier(attrs))
}

// kafkaHeaderCarrier is a read-only TextMapCarrier over Kafka message headers.
type kafkaHeaderCarrier []kafka.Header

var _ propagation.TextMapCarrier = kafkaHeaderCarrier(nil)

func (c kafkaHeaderCarrier) Get(key string) string {
	for _, h := range c {
		if h.Key == key {
			return string(h.Value)
		}
	}
	return ""
}

func (c kafkaHeaderCarrier) Keys() []string {
	keys := make([]string, len(c))
	for i, h := range c {
		keys[i] = h.Key
	}
	return keys
}

// Set is unused on the consume side (extraction only) but required by the
// interface.
func (c kafkaHeaderCarrier) Set(string, string) {}

// sqsAttributeCarrier is a read-only TextMapCarrier over SQS message attributes.
type sqsAttributeCarrier map[string]sqstypes.MessageAttributeValue

var _ propagation.TextMapCarrier = sqsAttributeCarrier(nil)

func (c sqsAttributeCarrier) Get(key string) string {
	if v, ok := c[key]; ok && v.StringValue != nil {
		return *v.StringValue
	}
	return ""
}

func (c sqsAttributeCarrier) Keys() []string {
	keys := make([]string, 0, len(c))
	for k := range c {
		keys = append(keys, k)
	}
	return keys
}

// Set is unused on the consume side (extraction only) but required by the
// interface.
func (c sqsAttributeCarrier) Set(string, string) {}
