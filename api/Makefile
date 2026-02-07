# Internal Developer Platform API Makefile

.PHONY: help build test swagger-validate run clean dev

# Default target
help:
	@echo "Available targets:"
	@echo "  build            - Build the application"
	@echo "  test             - Run tests"
	@echo "  swagger-validate - Validate the OpenAPI spec (docs/swagger.yaml)"
	@echo "  run              - Run the application"
	@echo "  clean            - Clean build artifacts"
	@echo "  dev              - Validate spec and build"

# Build the application
build:
	go build -o bin/server ./cmd/server

# Run tests
test:
	go test ./...

# Validate the hand-maintained OpenAPI spec
swagger-validate:
	@echo "Validating docs/swagger.yaml..."
	@command -v swagger-cli >/dev/null 2>&1 && swagger-cli validate docs/swagger.yaml || \
		echo "  (install swagger-cli for validation: npm install -g @apidevtools/swagger-cli)"

# Run the application
run: build
	./bin/server

# Clean build artifacts
clean:
	rm -rf bin/

# Development workflow: validate spec and build
dev: swagger-validate build

.DEFAULT_GOAL := help
