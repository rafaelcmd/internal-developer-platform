package telemetry

import (
	"fmt"

	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/sdk/resource"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
)

// newResource builds the OTel resource shared by every signal (metrics, traces,
// logs) so a single service is described identically across all three. The
// semconv attributes service.name / service.version / deployment.environment are
// what Datadog maps onto its service / version / env unified tags, so setting
// them here is what keeps the pipeline vendor-agnostic yet Datadog-friendly.
//
// NewSchemaless avoids a schema-URL conflict with resource.Default(), which
// carries its own semconv schema; the merged resource inherits the default's.
// resource.Default() also runs the env detector, so OTEL_RESOURCE_ATTRIBUTES /
// OTEL_SERVICE_NAME set on the pod are folded in on top of these.
func newResource(serviceName, serviceVersion, environment string) (*resource.Resource, error) {
	attrs := []attribute.KeyValue{
		semconv.ServiceName(serviceName),
		semconv.DeploymentEnvironment(environment),
	}
	if serviceVersion != "" {
		attrs = append(attrs, semconv.ServiceVersion(serviceVersion))
	}

	res, err := resource.Merge(resource.Default(), resource.NewSchemaless(attrs...))
	if err != nil {
		return nil, fmt.Errorf("building telemetry resource: %w", err)
	}
	return res, nil
}
