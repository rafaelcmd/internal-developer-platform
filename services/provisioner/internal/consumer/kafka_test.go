package consumer

import (
	"context"
	"testing"
	"time"

	"go.opentelemetry.io/otel"
)

// RunKafka must return promptly when the context is already cancelled, without
// needing a live broker (clean-shutdown path).
func TestRunKafka_CancelledContextReturnsPromptly(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	metrics := NewMetrics(otel.Meter("test"))
	done := make(chan error, 1)
	go func() {
		done <- RunKafka(ctx, KafkaConfig{
			Brokers: []string{"127.0.0.1:9092"},
			Topic:   "test-topic",
			GroupID: "test-group",
		}, otel.Tracer("test"), metrics)
	}()

	select {
	case err := <-done:
		if err == nil {
			t.Fatal("expected a context error on cancelled context")
		}
	case <-time.After(5 * time.Second):
		t.Fatal("RunKafka did not return on cancelled context")
	}
}
