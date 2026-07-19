package telemetry

import (
	"context"
	"fmt"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
)

// TracingConfig configures the OTLP trace pipeline.
type TracingConfig struct {
	ServiceName    string
	ServiceVersion string
	Environment    string
}

// Tracing owns the OTel TracerProvider that exports spans over OTLP/gRPC to the
// Collector. It carries no vendor coupling: the Collector decides where spans
// land (Datadog today). Callers must invoke Shutdown on teardown.
type Tracing struct {
	provider *sdktrace.TracerProvider
}

// NewTracing builds a TracerProvider wired to an OTLP/gRPC exporter, registers
// it as the OTel global, and installs the W3C trace-context + baggage
// propagators so distributed context flows across services.
//
// The exporter's endpoint and TLS mode are read from the standard OTEL_EXPORTER_
// OTLP_ENDPOINT / OTEL_EXPORTER_OTLP_INSECURE environment variables (set on the
// pod), keeping wiring out of code — point it at another backend without a
// rebuild.
func NewTracing(ctx context.Context, cfg TracingConfig) (*Tracing, error) {
	exporter, err := otlptracegrpc.New(ctx)
	if err != nil {
		return nil, fmt.Errorf("creating otlp trace exporter: %w", err)
	}

	res, err := newResource(cfg.ServiceName, cfg.ServiceVersion, cfg.Environment)
	if err != nil {
		return nil, err
	}

	provider := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
	)

	otel.SetTracerProvider(provider)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	return &Tracing{provider: provider}, nil
}

// Shutdown flushes buffered spans and releases the TracerProvider.
func (t *Tracing) Shutdown(ctx context.Context) error {
	return t.provider.Shutdown(ctx)
}
