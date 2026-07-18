package http

import (
	"net/http"
	"strings"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/metric"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
)

// meterName scopes instruments created by this package, following the OTel
// convention of using the instrumented package's import path.
const meterName = "github.com/rafaelcmd/internal-developer-platform/api/internal/adapters/inbound/http"

// metricsPath is the scrape endpoint, excluded from request instrumentation so
// Prometheus polling itself does not dominate the request-rate and latency
// series (a 15s scrape would otherwise be the most frequent "request").
const metricsPath = "/metrics"

// ActiveRequestsMiddleware tracks the number of in-flight HTTP requests on the
// OTel UpDownCounter http.server.active_requests: it increments when a request
// enters and decrements when it returns, so the Prometheus-exported gauge
// reflects concurrent request load at scrape time. Attributed with the request
// method only — the matched route and status code are not yet known while the
// request is still being served. Placed near the top of the chain so requests
// are counted for their whole lifetime; the decrement is deferred so a panic
// unwinding through this layer still releases the count.
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
		if r.URL.Path == metricsPath {
			next.ServeHTTP(w, r)
			return
		}
		attrs := metric.WithAttributes(semconv.HTTPRequestMethodKey.String(normalizeMethod(r.Method)))
		gauge.Add(r.Context(), 1, attrs)
		defer gauge.Add(r.Context(), -1, attrs)
		next.ServeHTTP(w, r)
	})
}

// RequestDurationMiddleware records the wall-clock latency of each HTTP request
// on the OTel histogram http.server.request.duration (unit: seconds, per OTel
// semconv), attributed with the request method, the matched route pattern, and
// the response status code. Its _count series doubles as the request counter, so
// request rate is rate(http_server_request_duration_seconds_count). It sits
// above the recovery layer, so a request whose panic is recovered below is timed
// and recorded with the 500 that layer writes.
func RequestDurationMiddleware(next http.Handler) http.Handler {
	histogram, err := otel.Meter(meterName).Float64Histogram(
		"http.server.request.duration",
		metric.WithDescription("Duration of inbound HTTP requests"),
		metric.WithUnit("s"),
	)
	if err != nil {
		// Instrument creation only fails on an invalid name; report through the
		// OTel error handler and serve uninstrumented rather than refuse traffic.
		otel.Handle(err)
		return next
	}

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == metricsPath {
			next.ServeHTTP(w, r)
			return
		}
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		elapsed := time.Since(start).Seconds()

		attrs := []attribute.KeyValue{
			semconv.HTTPRequestMethodKey.String(normalizeMethod(r.Method)),
			semconv.HTTPResponseStatusCode(rec.status),
		}
		// ServeMux sets Pattern on the request while routing, so it is readable
		// here once the inner handler returns. An empty pattern means no route
		// matched (404/405); omit http.route rather than record raw URL paths,
		// which would blow up label cardinality.
		if route := patternPath(r.Pattern); route != "" {
			attrs = append(attrs, semconv.HTTPRoute(route))
		}
		histogram.Record(r.Context(), elapsed, metric.WithAttributes(attrs...))
	})
}

// normalizeMethod maps the request method to one of the known HTTP methods,
// collapsing anything else to the semconv "_OTHER" sentinel. Go's server accepts
// arbitrary method tokens, so recording r.Method verbatim would let a client mint
// unbounded label values and blow up metric cardinality.
func normalizeMethod(method string) string {
	switch method {
	case http.MethodGet, http.MethodHead, http.MethodPost, http.MethodPut,
		http.MethodPatch, http.MethodDelete, http.MethodConnect,
		http.MethodOptions, http.MethodTrace:
		return method
	default:
		return "_OTHER"
	}
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
