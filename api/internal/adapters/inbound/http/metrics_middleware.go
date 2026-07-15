package http

import (
	"net/http"
	"strings"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/metric"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
)

// meterName scopes instruments created by this package, following the OTel
// convention of using the instrumented package's import path.
const meterName = "github.com/rafaelcmd/internal-developer-platform/api/internal/adapters/inbound/http"

// RequestCounterMiddleware counts completed HTTP requests on the OTel counter
// http.server.requests, attributed with the request method, the matched route
// pattern, and the response status code. It must be the outermost middleware:
// that way a panic recovered further down the chain is still counted with the
// 500 the recovery layer writes.
func RequestCounterMiddleware(next http.Handler) http.Handler {
	counter, err := otel.Meter(meterName).Int64Counter(
		"http.server.requests",
		metric.WithDescription("Number of HTTP requests handled by the server"),
		metric.WithUnit("{request}"),
	)
	if err != nil {
		// Instrument creation only fails on an invalid name; report through the
		// OTel error handler and serve uninstrumented rather than refuse traffic.
		otel.Handle(err)
		return next
	}

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)

		attrs := []attribute.KeyValue{
			semconv.HTTPRequestMethodKey.String(r.Method),
			semconv.HTTPResponseStatusCode(rec.status),
		}
		// ServeMux sets Pattern on the request while routing, so it is readable
		// here once the inner handler returns. An empty pattern means no route
		// matched (404/405); omit http.route rather than record raw URL paths,
		// which would blow up label cardinality.
		if route := patternPath(r.Pattern); route != "" {
			attrs = append(attrs, semconv.HTTPRoute(route))
		}
		counter.Add(r.Context(), 1, metric.WithAttributes(attrs...))
	})
}

// ActiveRequestsMiddleware tracks the number of in-flight HTTP requests on the
// OTel UpDownCounter http.server.active_requests: it increments when a request
// enters and decrements when it returns, so the Prometheus-exported gauge
// reflects concurrent request load at scrape time. Attributed with the request
// method only — unlike the request counter, the matched route and status code
// are not yet known while the request is still being served. Placed near the top
// of the chain so requests are counted for their whole lifetime; the decrement is
// deferred so a panic unwinding through this layer still releases the count.
func ActiveRequestsMiddleware(next http.Handler) http.Handler {
	gauge, err := otel.Meter(meterName).Int64UpDownCounter(
		"http.server.active_requests",
		metric.WithDescription("Number of in-flight HTTP requests"),
		metric.WithUnit("{request}"),
	)
	if err != nil {
		// Instrument creation only fails on an invalid name; report through the
		// OTel error handler and serve uninstrumented rather than refuse traffic.
		otel.Handle(err)
		return next
	}

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		attrs := metric.WithAttributes(semconv.HTTPRequestMethodKey.String(r.Method))
		gauge.Add(r.Context(), 1, attrs)
		defer gauge.Add(r.Context(), -1, attrs)
		next.ServeHTTP(w, r)
	})
}

// patternPath strips the optional "METHOD " prefix from a ServeMux pattern,
// leaving the path part used for the http.route attribute.
func patternPath(pattern string) string {
	if i := strings.IndexByte(pattern, ' '); i >= 0 {
		return pattern[i+1:]
	}
	return pattern
}

// statusRecorder captures the response status code for instrumentation. Unlike
// the idempotency responseRecorder it does not buffer the body.
type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(status int) {
	r.status = status
	r.ResponseWriter.WriteHeader(status)
}
