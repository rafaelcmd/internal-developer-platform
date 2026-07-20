package http

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/rafaelcmd/internal-developer-platform/api/internal/logger"
)

func newBufferLogger() (*bytes.Buffer, logger.Logger) {
	var buf bytes.Buffer
	return &buf, logger.New(logger.Config{Format: "json", Level: "info", Output: &buf})
}

func TestRequestLoggingMiddleware_LogsEveryRequest(t *testing.T) {
	buf, log := newBufferLogger()

	handler := RequestLoggingMiddleware(log)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusAccepted)
	}))

	req := httptest.NewRequest(http.MethodPost, "/v1/provision", nil)
	req.Header.Set("X-Request-Id", "req-123")
	handler.ServeHTTP(httptest.NewRecorder(), req)

	out := buf.String()
	assert.Contains(t, out, `"msg":"http request"`)
	assert.Contains(t, out, `"method":"POST"`)
	assert.Contains(t, out, `"route":"/v1/provision"`)
	assert.Contains(t, out, `"status":202`)
	assert.Contains(t, out, `"request_id":"req-123"`)
	assert.Contains(t, out, `"duration_ms":`)
}

func TestRequestLoggingMiddleware_SkipsMetricsEndpoint(t *testing.T) {
	buf, log := newBufferLogger()

	handler := RequestLoggingMiddleware(log)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
	handler.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/metrics", nil))

	assert.Empty(t, buf.String(), "the /metrics scrape endpoint must not be logged")
}

func TestRecoveryMiddleware_LogsPanicAndReturns500(t *testing.T) {
	buf, log := newBufferLogger()

	handler := RecoveryMiddleware(log)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		panic("boom")
	}))

	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/v1/provision", nil))

	assert.Equal(t, http.StatusInternalServerError, rec.Code)
	out := buf.String()
	assert.Contains(t, out, "panic recovered")
	assert.Contains(t, out, "boom")
}
