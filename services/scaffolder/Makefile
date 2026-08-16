# Internal Developer Platform Scaffolder Makefile

.PHONY: help restore build test test-unit test-integration coverage format format-check sam-build invoke clean

# Default target
help:
	@echo "Available targets:"
	@echo "  restore          - Restore NuGet packages"
	@echo "  build            - Build the solution"
	@echo "  test             - Run unit tests (no AWS, no Docker)"
	@echo "  test-integration - Run adapter tests against LocalStack and the sandbox org"
	@echo "  coverage         - Run unit tests with coverage collection"
	@echo "  format           - Apply formatting fixes"
	@echo "  format-check     - Verify formatting without changing files"
	@echo "  sam-build        - Build the SAM deployment artifacts"
	@echo "  invoke           - Invoke a function locally (F=ReserveName E=events/reserve-name.json)"
	@echo "  clean            - Remove build and SAM artifacts"

# Restore NuGet packages
restore:
	dotnet restore

# Build the solution
build:
	dotnet build

# Unit tests only: domain, application and handler wiring
test: test-unit

test-unit:
	dotnet test tests/Scaffolder.UnitTests

# Adapter tests. Opt-in because they need Docker and credentials.
test-integration:
	SCAFFOLDER_INTEGRATION=1 dotnet test tests/Scaffolder.IntegrationTests

# Coverage, in the shape the CI job publishes to the step summary
coverage:
	dotnet test tests/Scaffolder.UnitTests --collect:"XPlat Code Coverage"

# Formatting
format:
	dotnet format

format-check:
	dotnet format --verify-no-changes

# SAM. Requires template.yaml, which is not written yet.
F ?= ReserveName
E ?= events/reserve-name.json

sam-build:
	@test -f template.yaml || { echo "template.yaml does not exist yet"; exit 1; }
	sam build

invoke: sam-build
	sam local invoke $(F) -e $(E)

# Clean build artifacts
clean:
	dotnet clean
	rm -rf .aws-sam
	find . -type d \( -name bin -o -name obj \) -prune -exec rm -rf {} +

.DEFAULT_GOAL := help
