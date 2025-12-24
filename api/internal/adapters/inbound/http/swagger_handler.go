package http

import (
	"log"
	"net/http"
	"os"
	"strings"

	httpSwagger "github.com/swaggo/http-swagger"
)

type SwaggerHandler struct {
	swaggerFilePath string
}

func NewSwaggerHandler(swaggerFilePath string) *SwaggerHandler {
	// Verify the file exists at startup
	if _, err := os.Stat(swaggerFilePath); os.IsNotExist(err) {
		log.Printf("WARNING: swagger file not found at %s", swaggerFilePath)
	}
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
		log.Printf("SwaggerUI handler: URL.Path=%s, RequestURI=%s", r.URL.Path, r.RequestURI)

		path := r.URL.Path
		if path == "/swagger" {
			path = "/swagger/"
		}
		if strings.HasPrefix(path, "/swagger") {
			trimmed := strings.TrimPrefix(path, "/swagger")
			if trimmed == "" {
				trimmed = "/"
			}
			path = trimmed
		}

		if path == "/" {
			path = "/index.html"
		}

		if strings.HasSuffix(path, "swagger.yaml") {
			log.Printf("Serving swagger.yaml from %s", h.swaggerFilePath)
			h.ServeSwaggerFile(w, r)
			return
		}

		r2 := r.Clone(r.Context())
		r2.URL.Path = path
		r2.RequestURI = path

		swaggerUIHandler.ServeHTTP(w, r2)
	})
}
