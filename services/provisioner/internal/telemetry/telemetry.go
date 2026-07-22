// Package telemetry wires the provisioner into OpenTelemetry. It builds OTLP
// trace and metric pipelines to the OTel Collector, keeping the service
// vendor-agnostic: the Collector decides where telemetry lands (Datadog today),
// and this code never names a backend. Replaces the former AWS X-Ray SDK.
package telemetry

import (
	"context"
	"errors"
	"fmt"
	"os"

	"github.com/sirupsen/logrus"
	"go.opentelemetry.io/contrib/bridges/otellogrus"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploggrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	otellogglobal "go.opentelemetry.io/otel/log/global"
	"go.opentelemetry.io/otel/propagation"
	sdklog "go.opentelemetry.io/otel/sdk/log"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
)

// Config describes the service for the OTel resource.
type Config struct {
	ServiceName string
	Version     string
	Environment string
}

// Setup builds OTLP/gRPC trace, metric, and log pipelines, registers them as the
// OTel globals, and installs the W3C trace-context + baggage propagators. The
// exporter endpoint/TLS come from the standard OTEL_EXPORTER_OTLP_ENDPOINT /
// OTEL_EXPORTER_OTLP_INSECURE environment variables.
//
// It also returns a logrus Hook that mirrors application logs onto the OTLP log
// pipeline (carrying trace/span IDs from each entry's context so logs correlate
// with traces). Attach it to the logger via logger.Config.Hooks.
//
// When OTEL_EXPORTER_OTLP_ENDPOINT is unset — e.g. local Kafka dev with no
// Collector — Setup is a no-op: it leaves OTel's default no-op providers in
// place, returns a nil Hook and a nil-safe shutdown, so instrumentation calls
// cost nothing and logs still print to stdout. The returned shutdown flushes
// buffered telemetry and must be called on exit.
func Setup(ctx context.Context, cfg Config) (func(context.Context) error, logrus.Hook, error) {
	noop := func(context.Context) error { return nil }

	if os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT") == "" {
		return noop, nil, nil
	}

	res, err := newResource(cfg)
	if err != nil {
		return noop, nil, err
	}

	traceExporter, err := otlptracegrpc.New(ctx)
	if err != nil {
		return noop, nil, fmt.Errorf("creating otlp trace exporter: %w", err)
	}
	tracerProvider := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(traceExporter),
		sdktrace.WithResource(res),
	)
	otel.SetTracerProvider(tracerProvider)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	metricExporter, err := otlpmetricgrpc.New(ctx)
	if err != nil {
		return noop, nil, fmt.Errorf("creating otlp metric exporter: %w", err)
	}
	meterProvider := sdkmetric.NewMeterProvider(
		sdkmetric.WithReader(sdkmetric.NewPeriodicReader(metricExporter)),
		sdkmetric.WithResource(res),
	)
	otel.SetMeterProvider(meterProvider)

	// Log pipeline: put application logs on the same vendor-agnostic OTLP seam
	// as traces/metrics so they reach the backend (Datadog today) through the
	// Collector, correlated with traces via the trace/span IDs the logrus bridge
	// reads from each entry's context. logrus keeps writing JSON to stdout; the
	// hook mirrors each entry onto this pipeline.
	logExporter, err := otlploggrpc.New(ctx)
	if err != nil {
		return noop, nil, fmt.Errorf("creating otlp log exporter: %w", err)
	}
	loggerProvider := sdklog.NewLoggerProvider(
		sdklog.WithProcessor(sdklog.NewBatchProcessor(logExporter)),
		sdklog.WithResource(res),
	)
	otellogglobal.SetLoggerProvider(loggerProvider)
	hook := otellogrus.NewHook(cfg.ServiceName, otellogrus.WithLoggerProvider(loggerProvider))

	shutdown := func(ctx context.Context) error {
		return errors.Join(
			tracerProvider.Shutdown(ctx),
			meterProvider.Shutdown(ctx),
			loggerProvider.Shutdown(ctx),
		)
	}
	return shutdown, hook, nil
}

// newResource describes this service with the semconv attributes Datadog maps
// onto its service / version / env unified tags. NewSchemaless avoids a
// schema-URL clash with resource.Default(), whose env detector also folds in
// OTEL_RESOURCE_ATTRIBUTES / OTEL_SERVICE_NAME.
func newResource(cfg Config) (*resource.Resource, error) {
	attrs := []attribute.KeyValue{
		semconv.ServiceName(cfg.ServiceName),
		semconv.DeploymentEnvironment(cfg.Environment),
	}
	if cfg.Version != "" {
		attrs = append(attrs, semconv.ServiceVersion(cfg.Version))
	}

	res, err := resource.Merge(resource.Default(), resource.NewSchemaless(attrs...))
	if err != nil {
		return nil, fmt.Errorf("building telemetry resource: %w", err)
	}
	return res, nil
}
