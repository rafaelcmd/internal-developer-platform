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
	swaggerHandler := httpSwagger.Handler(
		httpSwagger.URL("swagger.yaml"),
	)

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Strip /swagger prefix and ensure path starts with /
		path := strings.TrimPrefix(r.URL.Path, "/swagger")
		if path == "" {
			path = "/"
		}
		r.URL.Path = path
		swaggerHandler.ServeHTTP(w, r)
	})
}
