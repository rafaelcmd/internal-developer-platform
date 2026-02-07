package config

import (
	"os"
	"testing"
	"time"
)

func TestNewConfig_DefaultValues(t *testing.T) {
	// Clear any existing environment variables
	os.Clearenv()

	cfg := NewConfig()

	// Test default server config
	if cfg.Server.Port != "8080" {
		t.Errorf("expected default port 8080, got %s", cfg.Server.Port)
	}
	if cfg.Server.ReadTimeout != 15*time.Second {
		t.Errorf("expected default read timeout 15s, got %v", cfg.Server.ReadTimeout)
	}

	// Test default AWS config
	if cfg.AWS.Region != "us-east-1" {
		t.Errorf("expected default region us-east-1, got %s", cfg.AWS.Region)
	}

	// Test default app config
	if cfg.App.Environment != "dev" {
		t.Errorf("expected default environment dev, got %s", cfg.App.Environment)
	}
	if cfg.App.LogLevel != "info" {
		t.Errorf("expected default log level info, got %s", cfg.App.LogLevel)
	}
}

func TestNewConfig_WithEnvironmentVariables(t *testing.T) {
	os.Clearenv()
	os.Setenv("PORT", "9090")
	os.Setenv("ENVIRONMENT", "production")
	os.Setenv("LOG_LEVEL", "debug")
	defer os.Clearenv()

	cfg := NewConfig()

	if cfg.Server.Port != "9090" {
		t.Errorf("expected port 9090, got %s", cfg.Server.Port)
	}
	if cfg.App.Environment != "production" {
		t.Errorf("expected environment production, got %s", cfg.App.Environment)
	}
	if cfg.App.LogLevel != "debug" {
		t.Errorf("expected log level debug, got %s", cfg.App.LogLevel)
	}
}

func TestNewConfig_WithOptions(t *testing.T) {
	os.Clearenv()

	cfg := NewConfig(
		WithPort("3000"),
		WithEnvironment("staging"),
		WithLogLevel("warn"),
	)

	if cfg.Server.Port != "3000" {
		t.Errorf("expected port 3000, got %s", cfg.Server.Port)
	}
	if cfg.App.Environment != "staging" {
		t.Errorf("expected environment staging, got %s", cfg.App.Environment)
	}
	if cfg.App.LogLevel != "warn" {
		t.Errorf("expected log level warn, got %s", cfg.App.LogLevel)
	}
}

func TestConfig_Validate_Success(t *testing.T) {
	cfg := NewConfig()
	err := cfg.Validate()

	if err != nil {
		t.Errorf("expected no validation error, got %v", err)
	}
}

func TestConfig_Validate_MissingPort(t *testing.T) {
	cfg := NewConfig()
	cfg.Server.Port = ""

	err := cfg.Validate()

	if err == nil {
		t.Error("expected validation error for missing port")
	}
}

func TestConfig_Validate_MissingQueueParam(t *testing.T) {
	cfg := NewConfig()
	cfg.AWS.ProvisionerQueueParamKey = ""

	err := cfg.Validate()

	if err == nil {
		t.Error("expected validation error for missing queue param key")
	}
}
