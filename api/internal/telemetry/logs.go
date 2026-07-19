package telemetry

import (
	"context"
	"fmt"

	"github.com/sirupsen/logrus"
	"go.opentelemetry.io/contrib/bridges/otellogrus"
	"go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploggrpc"
	otellogglobal "go.opentelemetry.io/otel/log/global"
	sdklog "go.opentelemetry.io/otel/sdk/log"
)

// LogsConfig configures the OTLP log pipeline.
type LogsConfig struct {
	ServiceName    string
	ServiceVersion string
	Environment    string
}

// Logs owns the OTel LoggerProvider that exports log records over OTLP/gRPC to
// the Collector, plus the logrus Hook that feeds application logs into it. The
// app keeps writing structured logs to logrus as before; the Hook mirrors each
// record onto the OTLP pipeline (carrying trace/span IDs from the entry's
// context, so logs correlate with traces). Callers must invoke Shutdown on
// teardown.
type Logs struct {
	provider *sdklog.LoggerProvider
	hook     logrus.Hook
}

// NewLogs builds a LoggerProvider wired to an OTLP/gRPC exporter, registers it
// as the OTel global, and returns a logrus Hook bound to it. Endpoint/TLS come
// from the standard OTEL_EXPORTER_OTLP_ENDPOINT / OTEL_EXPORTER_OTLP_INSECURE
// environment variables, same as the trace pipeline.
func NewLogs(ctx context.Context, cfg LogsConfig) (*Logs, error) {
	exporter, err := otlploggrpc.New(ctx)
	if err != nil {
		return nil, fmt.Errorf("creating otlp log exporter: %w", err)
	}

	res, err := newResource(cfg.ServiceName, cfg.ServiceVersion, cfg.Environment)
	if err != nil {
		return nil, err
	}

	provider := sdklog.NewLoggerProvider(
		sdklog.WithProcessor(sdklog.NewBatchProcessor(exporter)),
		sdklog.WithResource(res),
	)
	otellogglobal.SetLoggerProvider(provider)

	hook := otellogrus.NewHook(cfg.ServiceName, otellogrus.WithLoggerProvider(provider))

	return &Logs{provider: provider, hook: hook}, nil
}

// Hook returns the logrus Hook to attach to the application logger.
func (l *Logs) Hook() logrus.Hook {
	return l.hook
}

// Shutdown flushes buffered log records and releases the LoggerProvider.
func (l *Logs) Shutdown(ctx context.Context) error {
	return l.provider.Shutdown(ctx)
}
