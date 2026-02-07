package logger

import (
	"bytes"
	"context"
	"strings"
	"testing"
)

func TestNew_DefaultConfig(t *testing.T) {
	log := New(DefaultConfig())
	if log == nil {
		t.Error("New(DefaultConfig()) should not return nil")
	}
}

func TestLogger_Info(t *testing.T) {
	var buf bytes.Buffer
	log := New(Config{
		Level:  "info",
		Format: "json",
		Output: &buf,
	})

	log.Info("test message", F("key", "value"))

	output := buf.String()
	if !strings.Contains(output, "test message") {
		t.Errorf("expected output to contain 'test message', got %s", output)
	}
	if !strings.Contains(output, "key") {
		t.Errorf("expected output to contain 'key', got %s", output)
	}
}

func TestLogger_WithField(t *testing.T) {
	var buf bytes.Buffer
	log := New(Config{
		Level:  "info",
		Format: "json",
		Output: &buf,
	})

	log.WithField("request_id", "123").Info("test")

	output := buf.String()
	if !strings.Contains(output, "request_id") {
		t.Errorf("expected output to contain 'request_id', got %s", output)
	}
}

func TestLogger_WithFields(t *testing.T) {
	var buf bytes.Buffer
	log := New(Config{
		Level:  "info",
		Format: "json",
		Output: &buf,
	})

	log.WithFields(Fields{
		"key1": "value1",
		"key2": "value2",
	}).Info("test")

	output := buf.String()
	if !strings.Contains(output, "key1") {
		t.Errorf("expected output to contain 'key1', got %s", output)
	}
	if !strings.Contains(output, "key2") {
		t.Errorf("expected output to contain 'key2', got %s", output)
	}
}

func TestLogger_WithError(t *testing.T) {
	var buf bytes.Buffer
	log := New(Config{
		Level:  "info",
		Format: "json",
		Output: &buf,
	})

	err := &testError{msg: "test error"}
	log.WithError(err).Error("something went wrong")

	output := buf.String()
	if !strings.Contains(output, "test error") {
		t.Errorf("expected output to contain 'test error', got %s", output)
	}
}

func TestLogger_TextFormat(t *testing.T) {
	var buf bytes.Buffer
	log := New(Config{
		Level:  "info",
		Format: "text",
		Output: &buf,
	})

	log.Info("test message")

	output := buf.String()
	if !strings.Contains(output, "test message") {
		t.Errorf("expected output to contain 'test message', got %s", output)
	}
}

func TestNopLogger(t *testing.T) {
	log := NopLogger{}

	// These should not panic
	log.Debug("test")
	log.Info("test")
	log.Warn("test")
	log.Error("test")
	log.WithField("key", "value").Info("test")
	log.WithFields(Fields{"key": "value"}).Info("test")
	log.WithError(nil).Info("test")
	log.WithContext(context.Background()).Info("test")
}

func TestField(t *testing.T) {
	f := F("key", "value")
	if f.Key != "key" {
		t.Errorf("expected key 'key', got %s", f.Key)
	}
	if f.Value != "value" {
		t.Errorf("expected value 'value', got %v", f.Value)
	}
}

type testError struct {
	msg string
}

func (e *testError) Error() string {
	return e.msg
}
