// Package main is the entry point for the Internal Developer Platform API.
// It follows Clean Architecture principles with a minimal main function
// that delegates to the bootstrap package for dependency injection.
package main

import (
	"context"
	"os"

	"github.com/rafaelcmd/internal-developer-platform/api/internal/bootstrap"
	"github.com/rafaelcmd/internal-developer-platform/api/internal/config"
	"github.com/rafaelcmd/internal-developer-platform/api/internal/logger"
)

func main() {
	// Create a base context for the application
	ctx := context.Background()

	// Load configuration from environment
	cfg := config.NewConfig()
	if err := cfg.Validate(); err != nil {
		// Use a basic logger for configuration errors since the app isn't initialized yet
		log := logger.New(logger.DefaultConfig())
		log.Fatal("Configuration validation failed", logger.F("error", err.Error()))
	}

	// Initialize the application with all dependencies
	app, err := bootstrap.New(ctx, cfg, bootstrap.DefaultOptions())
	if err != nil {
		log := logger.New(logger.DefaultConfig())
		log.Fatal("Failed to initialize application", logger.F("error", err.Error()))
	}

	// Run the application (blocks until shutdown signal)
	if err := app.Run(ctx); err != nil {
		app.Logger.Error("Application error", logger.F("error", err.Error()))
		app.Shutdown()
		os.Exit(1)
	}

	// Graceful shutdown
	if err := app.Shutdown(); err != nil {
		app.Logger.Error("Shutdown error", logger.F("error", err.Error()))
		os.Exit(1)
	}
}
