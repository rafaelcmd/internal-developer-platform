package http

import (
	"fmt"
	"net/http"
	"runtime/debug"
	"time"

	"github.com/google/uuid"

	"github.com/rafaelcmd/internal-developer-platform/api/internal/logger"
)

// =============================================================================
// HTTP MIDDLEWARE
// Request/Response transformation middleware for consistent API behavior
// =============================================================================

// StandardHeadersMiddleware adds standard HTTP headers to all responses
// This includes security headers, caching directives, and request tracing
func StandardHeadersMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Generate or extract request ID for tracing
		requestID := r.Header.Get("X-Request-Id")
		if requestID == "" {
			requestID = r.Header.Get("X-Amzn-Trace-Id")
		}
		if requestID == "" {
			requestID = uuid.New().String()
		}

		// Set request ID in request header for downstream handlers
		r.Header.Set("X-Request-Id", requestID)

		// =================================================================
		// Response Headers - Set before calling next handler
		// =================================================================

		// Echo back request ID for client-side tracing
		w.Header().Set("X-Request-Id", requestID)

		// Security headers
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("X-XSS-Protection", "1; mode=block")

		// Cache control - default to no caching for API responses
		// Individual handlers can override this for cacheable resources
		w.Header().Set("Cache-Control", "no-store, no-cache, must-revalidate")
		w.Header().Set("Pragma", "no-cache")

		// API metadata headers
		w.Header().Set("X-API-Version", APIVersionPrefix[1:]) // Remove leading "/"

		// Timestamp for response timing
		w.Header().Set("X-Response-Time", time.Now().UTC().Format(time.RFC3339))

		next.ServeHTTP(w, r)
	})
}

// CORSMiddleware handles CORS preflight and response headers
// Note: API Gateway also handles CORS, this is for local development
func CORSMiddleware(allowedOrigins []string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			origin := r.Header.Get("Origin")

			// Check if origin is allowed
			allowed := false
			for _, o := range allowedOrigins {
				if o == "*" || o == origin {
					allowed = true
					break
				}
			}

			if allowed && origin != "" {
				w.Header().Set("Access-Control-Allow-Origin", origin)
				w.Header().Set("Access-Control-Allow-Credentials", "true")
				w.Header().Set("Access-Control-Expose-Headers", "X-Request-Id, X-API-Version, X-RateLimit-Limit, X-RateLimit-Remaining, X-RateLimit-Reset")
			}

			// Handle preflight requests
			if r.Method == http.MethodOptions {
				w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
				w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type, X-Request-Id, X-Idempotency-Key")
				w.Header().Set("Access-Control-Max-Age", "86400") // 24 hours
				w.WriteHeader(http.StatusNoContent)
				return
			}

			next.ServeHTTP(w, r)
		})
	}
}

// RequestContextMiddleware enriches requests with context information
// for logging and tracing purposes
func RequestContextMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Add request start time for latency tracking
		r.Header.Set("X-Request-Start", time.Now().UTC().Format(time.RFC3339Nano))

		next.ServeHTTP(w, r)
	})
}

// RequestLoggingMiddleware emits one structured log line per request — for
// every endpoint — with method, matched route, status, latency, and request ID.
// It wraps the response writer to capture the final status (including a 500 the
// recovery layer below writes) and logs after the handler returns. The request
// context is attached so the OTel log bridge correlates the line with the
// request's trace/span. The /metrics scrape endpoint is skipped so Prometheus
// polling doesn't flood the logs.
func RequestLoggingMiddleware(log logger.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.URL.Path == metricsPath {
				next.ServeHTTP(w, r)
				return
			}

			start := time.Now()
			rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
			next.ServeHTTP(rec, r)

			// ServeMux sets Pattern while routing; fall back to the raw path for
			// unmatched requests (404/405). Unlike metrics, logs can carry the
			// raw path — there is no cardinality budget to protect.
			route := patternPath(r.Pattern)
			if route == "" {
				route = r.URL.Path
			}

			log.WithContext(r.Context()).Info("http request",
				logger.F("method", r.Method),
				logger.F("route", route),
				logger.F("status", rec.status),
				logger.F("duration_ms", float64(time.Since(start).Microseconds())/1000),
				logger.F("request_id", r.Header.Get("X-Request-Id")),
			)
		})
	}
}

// RecoveryMiddleware catches panics, logs them with a stack trace, and returns a
// 500 error. Without the log, a panic on any route would 500 silently.
func RecoveryMiddleware(log logger.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			defer func() {
				if err := recover(); err != nil {
					requestID := r.Header.Get("X-Request-Id")
					log.WithContext(r.Context()).Error("http request panic recovered",
						logger.F("error", fmt.Sprintf("%v", err)),
						logger.F("method", r.Method),
						logger.F("path", r.URL.Path),
						logger.F("request_id", requestID),
						logger.F("stack", string(debug.Stack())),
					)
					RespondWithError(w, http.StatusInternalServerError, ErrorResponse{
						Code:      ErrCodeInternalError,
						Message:   "An unexpected error occurred",
						RequestID: requestID,
					})
				}
			}()

			next.ServeHTTP(w, r)
		})
	}
}

// ChainMiddleware chains multiple middleware functions together
func ChainMiddleware(handler http.Handler, middlewares ...func(http.Handler) http.Handler) http.Handler {
	// Apply in reverse order so first middleware is outermost
	for i := len(middlewares) - 1; i >= 0; i-- {
		handler = middlewares[i](handler)
	}
	return handler
}
