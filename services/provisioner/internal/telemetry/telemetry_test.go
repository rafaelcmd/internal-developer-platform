package telemetry

import (
	"context"
	"testing"
	"time"
)

// With no OTLP endpoint configured, Setup must be an inert no-op that still
// returns a usable shutdown — this is the local Kafka dev path.
func TestSetup_NoEndpoint_IsNoop(t *testing.T) {
	t.Setenv("OTEL_EXPORTER_OTLP_ENDPOINT", "")

	shutdown, _, err := Setup(context.Background(), Config{ServiceName: "test", Environment: "test"})
	if err != nil {
		t.Fatalf("Setup returned error: %v", err)
	}
	if shutdown == nil {
		t.Fatal("Setup returned nil shutdown")
	}
	if err := shutdown(context.Background()); err != nil {
		t.Fatalf("no-op shutdown returned error: %v", err)
	}
}

// With an endpoint set, Setup builds the pipelines (exporters connect lazily, so
// no live Collector is needed) and returns a shutdown that flushes within a
// bounded context.
func TestSetup_WithEndpoint_ConstructsAndShutsDown(t *testing.T) {
	t.Setenv("OTEL_EXPORTER_OTLP_ENDPOINT", "localhost:4317")
	t.Setenv("OTEL_EXPORTER_OTLP_INSECURE", "true")

	shutdown, _, err := Setup(context.Background(), Config{
		ServiceName: "test",
		Version:     "1.2.3",
		Environment: "test",
	})
	if err != nil {
		t.Fatalf("Setup returned error: %v", err)
	}
	if shutdown == nil {
		t.Fatal("Setup returned nil shutdown")
	}

	// Shutdown flushes to the (absent) Collector, so a network error here is
	// expected and best-effort; what we assert is that it returns promptly
	// within the bounded context rather than hanging.
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	done := make(chan struct{})
	go func() { _ = shutdown(ctx); close(done) }()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("shutdown did not return within deadline")
	}
}
