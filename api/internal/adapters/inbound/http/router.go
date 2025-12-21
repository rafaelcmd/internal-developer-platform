package http

import "net/http"

func NewRouter(resourceHandler *ResourceHandler, healthHandler *HealthHandler) http.Handler {
	mux := http.NewServeMux()

	// Handle POST /provision
	mux.HandleFunc("POST /provision", resourceHandler.Provision)

	// Handle GET /health
	mux.HandleFunc("GET /health", healthHandler.HealthCheck)

	return mux
}
