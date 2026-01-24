package http

import "net/http"

// API version prefix for path-based versioning
const APIVersionPrefix = "/v1"

// ServeMuxAdapter defines the interface for registering routes
type ServeMuxAdapter interface {
	Handle(pattern string, handler http.Handler)
	HandleFunc(pattern string, handler func(http.ResponseWriter, *http.Request))
}

func NewRouter(resourceHandler *ResourceHandler, healthHandler *HealthHandler, authHandler *AuthHandler, swaggerHandler *SwaggerHandler) http.Handler {
	mux := http.NewServeMux()

	// =============================================================================
	// API v1 Routes
	// All API endpoints use path-based versioning for backward compatibility
	// =============================================================================

	// Handle POST /v1/provision
	mux.HandleFunc("POST "+APIVersionPrefix+"/provision", resourceHandler.Provision)

	// Handle GET /v1/health
	mux.HandleFunc("GET "+APIVersionPrefix+"/health", healthHandler.HealthCheck)

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

	return mux
}
