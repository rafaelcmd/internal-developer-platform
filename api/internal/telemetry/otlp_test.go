package telemetry

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// The OTLP/gRPC exporters connect lazily, so the providers construct without a
// live Collector. These tests exercise construction, the returned logrus hook,
// and a bounded Shutdown (which must return even when the endpoint is dead).

func TestNewTracing_ConstructsAndShutsDown(t *testing.T) {
	t.Setenv("OTEL_EXPORTER_OTLP_ENDPOINT", "localhost:4317")
	t.Setenv("OTEL_EXPORTER_OTLP_INSECURE", "true")

	tracing, err := NewTracing(context.Background(), TracingConfig{
		ServiceName:    "test-service",
		ServiceVersion: "1.2.3",
		Environment:    "test",
	})
	require.NoError(t, err)
	require.NotNil(t, tracing)

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	assert.NoError(t, tracing.Shutdown(ctx))
}

func TestNewLogs_ReturnsHookAndShutsDown(t *testing.T) {
	t.Setenv("OTEL_EXPORTER_OTLP_ENDPOINT", "localhost:4317")
	t.Setenv("OTEL_EXPORTER_OTLP_INSECURE", "true")

	logs, err := NewLogs(context.Background(), LogsConfig{
		ServiceName:    "test-service",
		ServiceVersion: "1.2.3",
		Environment:    "test",
	})
	require.NoError(t, err)
	require.NotNil(t, logs)
	assert.NotNil(t, logs.Hook(), "hook must be attachable to logrus")

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	assert.NoError(t, logs.Shutdown(ctx))
}
