package http

import (
	"net/http"
	"os"

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
	env := os.Getenv("ENVIRONMENT")
	if env == "" {
		env = "dev"
	}
	swaggerYamlURL := "/" + env + "/swagger/swagger.yaml"
	return http.StripPrefix("/swagger/", httpSwagger.Handler(
		httpSwagger.URL(swaggerYamlURL),
	))
}
