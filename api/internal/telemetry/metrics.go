// Package telemetry wires the application into OpenTelemetry. It currently
// provides the metrics pipeline: an OTel MeterProvider backed by a Prometheus
// exporter, which is scraped over an HTTP endpoint.
package telemetry

import (
	"context"
	"fmt"
	"net/http"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.opentelemetry.io/otel"
	otelprom "go.opentelemetry.io/otel/exporters/prometheus"
	"go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
)

// MetricsConfig holds the configuration for the metrics provider.
type MetricsConfig struct {
	// ServiceName identifies this service in exported metric resource attributes.
	ServiceName string
	// Environment is the deployment environment (e.g. "dev", "prod").
	Environment string
}

// Metrics owns the metrics pipeline: the OTel MeterProvider and the HTTP
// handler that Prometheus scrapes. Callers must invoke Shutdown on teardown.
type Metrics struct {
	provider *metric.MeterProvider
	registry *prometheus.Registry
}

// NewMetrics builds an OTel MeterProvider backed by a Prometheus exporter and
// registers it as the global provider, so instrumentation obtained via
// otel.Meter is routed through it. The returned Metrics exposes the scrape
// Handler for the /metrics endpoint.
func NewMetrics(cfg MetricsConfig) (*Metrics, error) {
	// Use a dedicated registry rather than the global default so the exposed
	// endpoint only carries metrics produced by this provider.
	registry := prometheus.NewRegistry()

	exporter, err := otelprom.New(otelprom.WithRegisterer(registry))
	if err != nil {
		return nil, fmt.Errorf("creating prometheus exporter: %w", err)
	}

	// NewSchemaless avoids a schema-URL conflict with resource.Default(), which
	// carries its own semconv schema; the merged resource inherits the default's.
	res, err := resource.Merge(
		resource.Default(),
		resource.NewSchemaless(
			semconv.ServiceName(cfg.ServiceName),
			semconv.DeploymentEnvironment(cfg.Environment),
		),
	)
	if err != nil {
		return nil, fmt.Errorf("building telemetry resource: %w", err)
	}

	provider := metric.NewMeterProvider(
		metric.WithReader(exporter),
		metric.WithResource(res),
	)
	otel.SetMeterProvider(provider)

	return &Metrics{provider: provider, registry: registry}, nil
}

// Handler returns the HTTP handler that serves metrics in the Prometheus
// exposition format, intended to be mounted at /metrics.
func (m *Metrics) Handler() http.Handler {
	return promhttp.HandlerFor(m.registry, promhttp.HandlerOpts{})
}

// Shutdown flushes and releases the underlying MeterProvider.
func (m *Metrics) Shutdown(ctx context.Context) error {
	return m.provider.Shutdown(ctx)
}
