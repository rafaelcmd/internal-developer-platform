package http

import (
	"net/http"
	"strings"

	httpSwagger "github.com/swaggo/http-swagger"
)

type SwaggerHandler struct {
	swaggerFilePath string
}

func NewSwaggerHandler(swaggerFilePath string) *SwaggerHandler {
	return &SwaggerHandler{
		swaggerFilePath: swaggerFilePath,
	}
}

// ServeSwaggerFile serves the swagger.yaml file
func (h *SwaggerHandler) ServeSwaggerFile(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/yaml")
	http.ServeFile(w, r, h.swaggerFilePath)
}

// SwaggerUI returns the Swagger UI handler
func (h *SwaggerHandler) SwaggerUI() http.Handler {
	swaggerUIHandler := httpSwagger.Handler(
		httpSwagger.URL("swagger.yaml"),
	)

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Serve swagger.yaml from our file
		if strings.HasSuffix(r.URL.Path, "swagger.yaml") || strings.HasSuffix(r.RequestURI, "swagger.yaml") {
			w.Header().Set("Content-Type", "application/yaml")
			http.ServeFile(w, r, h.swaggerFilePath)
			return
		}
		// Let httpSwagger handle everything else
		swaggerUIHandler.ServeHTTP(w, r)
	})
}
