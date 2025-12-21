package http

import "net/http"

func NewRouter(resourceHandler *ResourceHandler, healthHandler *HealthHandler) http.Handler {
	mux := http.NewServeMux()

	// Handle /provision and /prod/provision (in case API Gateway forwards the stage)
	provisionHandler := func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		resourceHandler.Provision(w, r)
	}
	mux.HandleFunc("/provision", provisionHandler)
	mux.HandleFunc("/prod/provision", provisionHandler)

	// Handle /health and /prod/health
	healthHandlerFunc := func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		healthHandler.HealthCheck(w, r)
	}
	mux.HandleFunc("/health", healthHandlerFunc)
	mux.HandleFunc("/prod/health", healthHandlerFunc)

	return mux
}
