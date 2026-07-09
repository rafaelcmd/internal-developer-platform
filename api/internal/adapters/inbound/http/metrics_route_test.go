package http

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/rafaelcmd/internal-developer-platform/api/internal/telemetry"
)

func TestRouter_MetricsEndpoint_ServesPrometheus(t *testing.T) {
	// Arrange: a router configured with a real Prometheus-backed metrics handler.
	metrics, err := telemetry.NewMetrics(telemetry.MetricsConfig{
		ServiceName: "test-service",
		Environment: "test",
	})
	assert.NoError(t, err)

	config := DefaultRouterConfig()
	config.MetricsHandler = metrics.Handler()
	router := NewRouterWithConfig(nil, nil, nil, nil, config)

	req := httptest.NewRequest(http.MethodGet, "/metrics", nil)
	rec := httptest.NewRecorder()

	// Act
	router.ServeHTTP(rec, req)

	// Assert: the endpoint responds with the Prometheus exposition format.
	assert.Equal(t, http.StatusOK, rec.Code)
	assert.Contains(t, rec.Header().Get("Content-Type"), "text/plain")
}

func TestRouter_MetricsEndpoint_NotRegisteredWhenNil(t *testing.T) {
	// Arrange: no metrics handler configured.
	router := NewRouterWithConfig(nil, nil, nil, nil, DefaultRouterConfig())

	req := httptest.NewRequest(http.MethodGet, "/metrics", nil)
	rec := httptest.NewRecorder()

	// Act
	router.ServeHTTP(rec, req)

	// Assert: route is absent.
	assert.Equal(t, http.StatusNotFound, rec.Code)
}
