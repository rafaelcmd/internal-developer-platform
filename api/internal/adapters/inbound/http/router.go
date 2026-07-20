package http

import (
	"net/http"
	"time"

	"github.com/rafaelcmd/internal-developer-platform/api/internal/domain/ports/outbound"
	"github.com/rafaelcmd/internal-developer-platform/api/internal/logger"
)

// API version prefix for path-based versioning
const APIVersionPrefix = "/v1"

// ServeMuxAdapter defines the interface for registering routes
type ServeMuxAdapter interface {
	Handle(pattern string, handler http.Handler)
	HandleFunc(pattern string, handler func(http.ResponseWriter, *http.Request))
}

// RouterConfig holds configuration for the router
type RouterConfig struct {
	// AllowedOrigins for CORS (used in local development, API Gateway handles CORS in production)
	AllowedOrigins []string

	// IdempotencyStore backs the idempotency middleware on mutating routes. If nil,
	// the middleware is skipped — useful for tests that don't exercise the layer.
	IdempotencyStore outbound.IdempotencyStore

	// IdempotencyTTL controls how long stored responses are replayable.
	IdempotencyTTL time.Duration

	// MetricsHandler serves the Prometheus scrape endpoint at GET /metrics. If nil,
	// the route is not registered — useful for tests that don't exercise telemetry.
	MetricsHandler http.Handler

	// Logger backs the request-logging and recovery middleware. If nil, a no-op
	// logger is used — useful for tests that don't assert on logs.
	Logger logger.Logger
}

// DefaultRouterConfig returns default router configuration
func DefaultRouterConfig() RouterConfig {
	return RouterConfig{
		AllowedOrigins: []string{"*"},
		IdempotencyTTL: 24 * time.Hour,
	}
}

func NewRouter(resourceHandler *ResourceHandler, healthHandler *HealthHandler, authHandler *AuthHandler, swaggerHandler *SwaggerHandler) http.Handler {
	return NewRouterWithConfig(resourceHandler, healthHandler, authHandler, swaggerHandler, DefaultRouterConfig())
}

func NewRouterWithConfig(resourceHandler *ResourceHandler, healthHandler *HealthHandler, authHandler *AuthHandler, swaggerHandler *SwaggerHandler, config RouterConfig) http.Handler {
	mux := http.NewServeMux()

	// =============================================================================
	// API v1 Routes
	// All API endpoints use path-based versioning for backward compatibility
	// =============================================================================

	// POST /v1/provision is wrapped in the idempotency middleware so retries are deduped.
	provisionHandler := http.HandlerFunc(resourceHandler.Provision)
	if config.IdempotencyStore != nil {
		ttl := config.IdempotencyTTL
		if ttl == 0 {
			ttl = 24 * time.Hour
		}
		mux.Handle("POST "+APIVersionPrefix+"/provision", IdempotencyMiddleware(config.IdempotencyStore, ttl)(provisionHandler))
	} else {
		mux.Handle("POST "+APIVersionPrefix+"/provision", provisionHandler)
	}

	// Handle GET /v1/health
	mux.HandleFunc("GET "+APIVersionPrefix+"/health", healthHandler.HealthCheck)

	// Expose Prometheus metrics at the conventional unversioned /metrics path so
	// standard scrape configurations work without a version prefix.
	if config.MetricsHandler != nil {
		mux.Handle("GET /metrics", config.MetricsHandler)
	}

	// Handle POST /v1/auth/signup
	mux.HandleFunc("POST "+APIVersionPrefix+"/auth/signup", authHandler.SignUp)

	// Handle POST /v1/auth/signin
	mux.HandleFunc("POST "+APIVersionPrefix+"/auth/signin", authHandler.SignIn)

	// Handle POST /v1/auth/confirm
	mux.HandleFunc("POST "+APIVersionPrefix+"/auth/confirm", authHandler.ConfirmSignUp)

	// Handle Swagger UI - must be registered before other /swagger routes
	// The httpSwagger.Handler expects to receive requests with /swagger/ prefix in RequestURI
	swaggerUI := swaggerHandler.SwaggerUI()
	mux.Handle("GET "+APIVersionPrefix+"/swagger", swaggerUI)
	mux.Handle("GET "+APIVersionPrefix+"/swagger/", swaggerUI)

	// A nil logger (e.g. in tests) degrades to a no-op rather than panicking.
	log := config.Logger
	if log == nil {
		log = logger.NopLogger{}
	}

	// =============================================================================
	// Middleware Chain
	// Applied in order (outermost first):
	//   ActiveRequests -> RequestDuration -> RequestLogging -> Recovery ->
	//   RequestContext -> StandardHeaders -> CORS -> Routes
	// ActiveRequests is outermost so in-flight requests are gauged for their whole
	// lifetime. RequestLogging and RequestDuration sit above Recovery so a
	// recovered panic is logged and timed with the 500 that layer writes; the
	// histogram _count series doubles as the request counter (rate = rate of _count).
	// =============================================================================
	return ChainMiddleware(
		mux,
		ActiveRequestsMiddleware,
		RequestDurationMiddleware,
		RequestLoggingMiddleware(log),
		RecoveryMiddleware(log),
		RequestContextMiddleware,
		StandardHeadersMiddleware,
		CORSMiddleware(config.AllowedOrigins),
	)
}
