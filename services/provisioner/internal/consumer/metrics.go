// Package consumer holds the message-consumption loops. The transport is chosen
// at startup: Kafka for local dev (no AWS), SQS otherwise. Both share the same
// telemetry (spans + these counters).
package consumer

import "go.opentelemetry.io/otel/metric"

// Metrics are the counters both transports report.
type Metrics struct {
	Received  metric.Int64Counter
	Processed metric.Int64Counter
	Failed    metric.Int64Counter
}

// NewMetrics creates the provisioner message counters on the given meter.
func NewMetrics(meter metric.Meter) Metrics {
	received, _ := meter.Int64Counter("provisioner.messages.received",
		metric.WithDescription("Messages received from the provisioning queue"))
	processed, _ := meter.Int64Counter("provisioner.messages.processed",
		metric.WithDescription("Messages processed and acknowledged successfully"))
	failed, _ := meter.Int64Counter("provisioner.messages.failed",
		metric.WithDescription("Messages that failed to acknowledge after processing"))
	return Metrics{Received: received, Processed: processed, Failed: failed}
}
