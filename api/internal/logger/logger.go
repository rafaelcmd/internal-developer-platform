// Package logger provides structured logging capabilities for the application.
// It wraps logrus with a clean interface and supports different output formats.
package logger

import (
	"context"
	"io"
	"os"

	"github.com/sirupsen/logrus"
)

// Logger defines the interface for application logging.
// This abstraction allows for easy mocking in tests and potential future replacement.
type Logger interface {
	Debug(msg string, fields ...Field)
	Info(msg string, fields ...Field)
	Warn(msg string, fields ...Field)
	Error(msg string, fields ...Field)
	Fatal(msg string, fields ...Field)
	WithField(key string, value interface{}) Logger
	WithFields(fields Fields) Logger
	WithError(err error) Logger
	WithContext(ctx context.Context) Logger
}

// Field represents a key-value pair for structured logging.
type Field struct {
	Key   string
	Value interface{}
}

// Fields is a map of key-value pairs for structured logging.
type Fields map[string]interface{}

// F creates a new Field.
func F(key string, value interface{}) Field {
	return Field{Key: key, Value: value}
}

// logrusLogger implements Logger using logrus.
type logrusLogger struct {
	entry *logrus.Entry
}

// Config holds logger configuration.
type Config struct {
	Level      string
	Format     string // "json" or "text"
	Output     io.Writer
	TimeFormat string
}

// DefaultConfig returns the default logger configuration.
func DefaultConfig() Config {
	return Config{
		Level:      "info",
		Format:     "json",
		Output:     os.Stdout,
		TimeFormat: "2006-01-02T15:04:05.000Z07:00",
	}
}

// New creates a new Logger with the given configuration.
func New(cfg Config) Logger {
	log := logrus.New()

	// Set output
	if cfg.Output != nil {
		log.SetOutput(cfg.Output)
	}

	// Set level
	level, err := logrus.ParseLevel(cfg.Level)
	if err != nil {
		level = logrus.InfoLevel
	}
	log.SetLevel(level)

	// Set formatter
	switch cfg.Format {
	case "text":
		log.SetFormatter(&logrus.TextFormatter{
			TimestampFormat: cfg.TimeFormat,
			FullTimestamp:   true,
		})
	default:
		log.SetFormatter(&logrus.JSONFormatter{
			TimestampFormat: cfg.TimeFormat,
		})
	}

	return &logrusLogger{entry: logrus.NewEntry(log)}
}

// NewWithLogrus creates a Logger from an existing logrus.Entry.
// Useful for integrating with existing logrus setups.
func NewWithLogrus(entry *logrus.Entry) Logger {
	return &logrusLogger{entry: entry}
}

func (l *logrusLogger) Debug(msg string, fields ...Field) {
	l.withFields(fields).Debug(msg)
}

func (l *logrusLogger) Info(msg string, fields ...Field) {
	l.withFields(fields).Info(msg)
}

func (l *logrusLogger) Warn(msg string, fields ...Field) {
	l.withFields(fields).Warn(msg)
}

func (l *logrusLogger) Error(msg string, fields ...Field) {
	l.withFields(fields).Error(msg)
}

func (l *logrusLogger) Fatal(msg string, fields ...Field) {
	l.withFields(fields).Fatal(msg)
}

func (l *logrusLogger) WithField(key string, value interface{}) Logger {
	return &logrusLogger{entry: l.entry.WithField(key, value)}
}

func (l *logrusLogger) WithFields(fields Fields) Logger {
	return &logrusLogger{entry: l.entry.WithFields(logrus.Fields(fields))}
}

func (l *logrusLogger) WithError(err error) Logger {
	return &logrusLogger{entry: l.entry.WithError(err)}
}

func (l *logrusLogger) WithContext(ctx context.Context) Logger {
	return &logrusLogger{entry: l.entry.WithContext(ctx)}
}

func (l *logrusLogger) withFields(fields []Field) *logrus.Entry {
	if len(fields) == 0 {
		return l.entry
	}

	logrusFields := make(logrus.Fields, len(fields))
	for _, f := range fields {
		logrusFields[f.Key] = f.Value
	}
	return l.entry.WithFields(logrusFields)
}

// NopLogger is a logger that does nothing. Useful for testing.
type NopLogger struct{}

func (NopLogger) Debug(msg string, fields ...Field)              {}
func (NopLogger) Info(msg string, fields ...Field)               {}
func (NopLogger) Warn(msg string, fields ...Field)               {}
func (NopLogger) Error(msg string, fields ...Field)              {}
func (NopLogger) Fatal(msg string, fields ...Field)              {}
func (NopLogger) WithField(key string, value interface{}) Logger { return NopLogger{} }
func (NopLogger) WithFields(fields Fields) Logger                { return NopLogger{} }
func (NopLogger) WithError(err error) Logger                     { return NopLogger{} }
func (NopLogger) WithContext(ctx context.Context) Logger         { return NopLogger{} }
