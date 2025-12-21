package http

import "net/http"

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
