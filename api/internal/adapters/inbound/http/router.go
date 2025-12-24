package http

import "net/http"

// ServeMuxAdapter defines the interface for registering routes
type ServeMuxAdapter interface {
	Handle(pattern string, handler http.Handler)
	HandleFunc(pattern string, handler func(http.ResponseWriter, *http.Request))
}

func NewRouter(resourceHandler *ResourceHandler, healthHandler *HealthHandler, authHandler *AuthHandler) http.Handler {
	mux := http.NewServeMux()

	// Handle POST /provision
	mux.HandleFunc("POST /provision", resourceHandler.Provision)

	// Handle GET /health
	mux.HandleFunc("GET /health", healthHandler.HealthCheck)

	// Handle POST /auth/signup
	mux.HandleFunc("POST /auth/signup", authHandler.SignUp)

	// Handle POST /auth/signin
	mux.HandleFunc("POST /auth/signin", authHandler.SignIn)

	return mux
}

// RegisterSwaggerRoutes registers swagger routes on the given mux
func RegisterSwaggerRoutes(mux ServeMuxAdapter, swaggerHandler *SwaggerHandler) {
	mux.HandleFunc("GET /swagger/swagger.yaml", swaggerHandler.ServeSwaggerFile)
	mux.Handle("/swagger/", swaggerHandler.SwaggerUI())
}
