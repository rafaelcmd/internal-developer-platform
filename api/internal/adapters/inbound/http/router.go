package http

import "net/http"

func NewRouter(resourceHandler *ResourceHandler, healthHandler *HealthHandler) http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("/provision", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		resourceHandler.Provision(w, r)
	})

	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		healthHandler.HealthCheck(w, r)
	})

	return mux
}
