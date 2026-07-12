package http

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/rafaelcmd/internal-developer-platform/api/internal/telemetry"
)

// newInstrumentedRouter builds a router backed by a real Prometheus-exporting
// metrics pipeline, so tests can drive requests and read the scrape output.
func newInstrumentedRouter(t *testing.T) http.Handler {
	t.Helper()

	metrics, err := telemetry.NewMetrics(telemetry.MetricsConfig{
		ServiceName: "test-service",
		Environment: "test",
	})
	require.NoError(t, err)
	t.Cleanup(func() { _ = metrics.Shutdown(t.Context()) })

	config := DefaultRouterConfig()
	config.MetricsHandler = metrics.Handler()
	return NewRouterWithConfig(nil, NewHealthHandler(), nil, nil, config)
}

func scrape(t *testing.T, router http.Handler) string {
	t.Helper()

	req := httptest.NewRequest(http.MethodGet, "/metrics", nil)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	require.Equal(t, http.StatusOK, rec.Code)
	return rec.Body.String()
}

func TestRequestCounterMiddleware_CountsMatchedRoute(t *testing.T) {
	router := newInstrumentedRouter(t)

	// Act: serve a routed request, then scrape.
	req := httptest.NewRequest(http.MethodGet, "/v1/health", nil)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	require.Equal(t, http.StatusOK, rec.Code)

	body := scrape(t, router)

	// Assert: the counter appears with method, route pattern, and status labels.
	line := findMetricLine(body, "http_server_requests_total", `http_route="/v1/health"`)
	require.NotEmpty(t, line, "expected a http_server_requests_total sample for /v1/health, got:\n%s", body)
	assert.Contains(t, line, `http_request_method="GET"`)
	assert.Contains(t, line, `http_response_status_code="200"`)
	assert.True(t, strings.HasSuffix(line, " 1"), "expected a count of 1, got: %s", line)
}

func TestRequestCounterMiddleware_CountsUnmatchedRouteWithoutRouteLabel(t *testing.T) {
	router := newInstrumentedRouter(t)

	// Act: serve a request that matches no route, then scrape.
	req := httptest.NewRequest(http.MethodGet, "/no-such-route", nil)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	require.Equal(t, http.StatusNotFound, rec.Code)

	body := scrape(t, router)

	// Assert: the 404 is counted but carries no http_route label, since raw
	// unmatched paths would create unbounded label cardinality.
	line := findMetricLine(body, "http_server_requests_total", `http_response_status_code="404"`)
	require.NotEmpty(t, line, "expected a http_server_requests_total sample for the 404, got:\n%s", body)
	assert.NotContains(t, line, "http_route=")
}

// findMetricLine returns the first sample line of the given metric that also
// contains the given label fragment, or "" if none matches.
func findMetricLine(body, metric, labelFragment string) string {
	for _, line := range strings.Split(body, "\n") {
		if strings.HasPrefix(line, metric) && strings.Contains(line, labelFragment) {
			return line
		}
	}
	return ""
}
