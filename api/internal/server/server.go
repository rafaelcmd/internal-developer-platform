// Package server provides HTTP server lifecycle management.
// It encapsulates server configuration, startup, and graceful shutdown.
package server

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/rafaelcmd/internal-developer-platform/api/internal/logger"
)

// Config holds HTTP server configuration.
type Config struct {
	Port            string
	ReadTimeout     time.Duration
	WriteTimeout    time.Duration
	IdleTimeout     time.Duration
	ShutdownTimeout time.Duration
}

// DefaultConfig returns sensible default server configuration.
func DefaultConfig() Config {
	return Config{
		Port:            "8080",
		ReadTimeout:     15 * time.Second,
		WriteTimeout:    15 * time.Second,
		IdleTimeout:     60 * time.Second,
		ShutdownTimeout: 30 * time.Second,
	}
}

// Server wraps http.Server with lifecycle management.
type Server struct {
	httpServer *http.Server
	config     Config
	logger     logger.Logger
}

// New creates a new Server with the given handler and configuration.
func New(handler http.Handler, cfg Config, log logger.Logger) *Server {
	return &Server{
		httpServer: &http.Server{
			Addr:         ":" + cfg.Port,
			Handler:      handler,
			ReadTimeout:  cfg.ReadTimeout,
			WriteTimeout: cfg.WriteTimeout,
			IdleTimeout:  cfg.IdleTimeout,
		},
		config: cfg,
		logger: log,
	}
}

// Start starts the HTTP server and blocks until it receives a shutdown signal.
// It handles graceful shutdown automatically.
func (s *Server) Start(ctx context.Context) error {
	// Channel to receive server errors
	serverErrors := make(chan error, 1)

	// Start server in a goroutine
	go func() {
		s.logger.Info("Starting HTTP server", logger.F("port", s.config.Port))
		if err := s.httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			serverErrors <- err
		}
	}()

	// Wait for interrupt signal or server error
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)

	select {
	case err := <-serverErrors:
		return fmt.Errorf("server error: %w", err)
	case sig := <-quit:
		s.logger.Info("Received shutdown signal", logger.F("signal", sig.String()))
	case <-ctx.Done():
		s.logger.Info("Context cancelled")
	}

	return s.Shutdown()
}

// Shutdown gracefully shuts down the server.
func (s *Server) Shutdown() error {
	s.logger.Info("Initiating graceful shutdown")

	ctx, cancel := context.WithTimeout(context.Background(), s.config.ShutdownTimeout)
	defer cancel()

	if err := s.httpServer.Shutdown(ctx); err != nil {
		s.logger.Error("Server forced to shutdown", logger.F("error", err.Error()))
		return fmt.Errorf("server shutdown error: %w", err)
	}

	s.logger.Info("Server stopped gracefully")
	return nil
}

// ListenAndServe starts the server without blocking for shutdown signals.
// Useful when you want to manage the lifecycle externally.
func (s *Server) ListenAndServe() error {
	s.logger.Info("Starting HTTP server", logger.F("port", s.config.Port))
	return s.httpServer.ListenAndServe()
}

// Addr returns the server's address.
func (s *Server) Addr() string {
	return s.httpServer.Addr
}
