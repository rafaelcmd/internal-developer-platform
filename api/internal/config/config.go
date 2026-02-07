// Package config provides application configuration management following 12-factor app principles.
// Configuration is loaded from environment variables with validation and sensible defaults.
package config

import (
	"errors"
	"fmt"
	"os"
	"strconv"
	"time"
)

// Config holds all application configuration.
type Config struct {
	// Server configuration
	Server ServerConfig

	// AWS configuration
	AWS AWSConfig

	// Feature flags and application settings
	App AppConfig
}

// ServerConfig holds HTTP server configuration.
type ServerConfig struct {
	Port            string
	ReadTimeout     time.Duration
	WriteTimeout    time.Duration
	IdleTimeout     time.Duration
	ShutdownTimeout time.Duration
}

// AWSConfig holds AWS-related configuration.
type AWSConfig struct {
	Region                   string
	ProvisionerQueueParamKey string
	CognitoClientIDParamKey  string
}

// AppConfig holds application-specific configuration.
type AppConfig struct {
	Environment    string
	LogLevel       string
	AllowedOrigins []string
	EnableTracing  bool
	ServiceName    string
}

// Option defines a functional option for Config.
type Option func(*Config)

// ErrMissingConfig is returned when a required configuration value is missing.
var ErrMissingConfig = errors.New("missing required configuration")

// NewConfig creates a new Config with default values and applies any options.
func NewConfig(opts ...Option) *Config {
	cfg := &Config{
		Server: ServerConfig{
			Port:            getEnvOrDefault("PORT", "8080"),
			ReadTimeout:     getDurationEnv("SERVER_READ_TIMEOUT", 15*time.Second),
			WriteTimeout:    getDurationEnv("SERVER_WRITE_TIMEOUT", 15*time.Second),
			IdleTimeout:     getDurationEnv("SERVER_IDLE_TIMEOUT", 60*time.Second),
			ShutdownTimeout: getDurationEnv("SERVER_SHUTDOWN_TIMEOUT", 30*time.Second),
		},
		AWS: AWSConfig{
			Region:                   getEnvOrDefault("AWS_REGION", "us-east-1"),
			ProvisionerQueueParamKey: getEnvOrDefault("PROVISIONER_QUEUE_PARAM_KEY", "/INTERNAL_DEVELOPER_PLATFORM/PROVISIONER_QUEUE_URL"),
			CognitoClientIDParamKey:  getEnvOrDefault("COGNITO_CLIENT_ID_PARAM_KEY", "/INTERNAL_DEVELOPER_PLATFORM/COGNITO_CLIENT_ID"),
		},
		App: AppConfig{
			Environment:    getEnvOrDefault("ENVIRONMENT", "dev"),
			LogLevel:       getEnvOrDefault("LOG_LEVEL", "info"),
			AllowedOrigins: getSliceEnv("ALLOWED_ORIGINS", []string{"*"}),
			EnableTracing:  getBoolEnv("ENABLE_TRACING", true),
			ServiceName:    getEnvOrDefault("SERVICE_NAME", "internal-developer-platform.api"),
		},
	}

	for _, opt := range opts {
		opt(cfg)
	}

	return cfg
}

// Validate validates the configuration and returns an error if invalid.
func (c *Config) Validate() error {
	if c.Server.Port == "" {
		return fmt.Errorf("%w: server port", ErrMissingConfig)
	}
	if c.AWS.ProvisionerQueueParamKey == "" {
		return fmt.Errorf("%w: provisioner queue param key", ErrMissingConfig)
	}
	if c.AWS.CognitoClientIDParamKey == "" {
		return fmt.Errorf("%w: cognito client id param key", ErrMissingConfig)
	}
	return nil
}

// WithPort sets the server port.
func WithPort(port string) Option {
	return func(c *Config) {
		c.Server.Port = port
	}
}

// WithEnvironment sets the application environment.
func WithEnvironment(env string) Option {
	return func(c *Config) {
		c.App.Environment = env
	}
}

// WithLogLevel sets the log level.
func WithLogLevel(level string) Option {
	return func(c *Config) {
		c.App.LogLevel = level
	}
}

// Helper functions for environment variable parsing

func getEnvOrDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func getDurationEnv(key string, defaultValue time.Duration) time.Duration {
	if value := os.Getenv(key); value != "" {
		if d, err := time.ParseDuration(value); err == nil {
			return d
		}
	}
	return defaultValue
}

func getBoolEnv(key string, defaultValue bool) bool {
	if value := os.Getenv(key); value != "" {
		if b, err := strconv.ParseBool(value); err == nil {
			return b
		}
	}
	return defaultValue
}

func getSliceEnv(key string, defaultValue []string) []string {
	if value := os.Getenv(key); value != "" {
		// Simple split by comma for now, could be enhanced
		return splitAndTrim(value, ",")
	}
	return defaultValue
}

func splitAndTrim(s, sep string) []string {
	var result []string
	for _, part := range splitString(s, sep) {
		trimmed := trimSpace(part)
		if trimmed != "" {
			result = append(result, trimmed)
		}
	}
	return result
}

// splitString splits a string by separator without using strings package
func splitString(s, sep string) []string {
	if len(sep) == 0 {
		return []string{s}
	}

	var result []string
	start := 0
	for i := 0; i <= len(s)-len(sep); i++ {
		if s[i:i+len(sep)] == sep {
			result = append(result, s[start:i])
			start = i + len(sep)
			i = start - 1
		}
	}
	result = append(result, s[start:])
	return result
}

// trimSpace trims leading and trailing whitespace
func trimSpace(s string) string {
	start := 0
	end := len(s)
	for start < end && (s[start] == ' ' || s[start] == '\t' || s[start] == '\n' || s[start] == '\r') {
		start++
	}
	for end > start && (s[end-1] == ' ' || s[end-1] == '\t' || s[end-1] == '\n' || s[end-1] == '\r') {
		end--
	}
	return s[start:end]
}
