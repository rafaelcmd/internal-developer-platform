// Package errors provides domain-specific error types for the application.
// These errors follow Clean Architecture principles by keeping domain errors
// separate from infrastructure concerns.
package errors

import (
	"errors"
	"fmt"
)

// Standard sentinel errors for common error conditions.
var (
	// ErrNotFound indicates that a requested resource was not found.
	ErrNotFound = errors.New("resource not found")

	// ErrAlreadyExists indicates that a resource already exists.
	ErrAlreadyExists = errors.New("resource already exists")

	// ErrInvalidInput indicates that the input validation failed.
	ErrInvalidInput = errors.New("invalid input")

	// ErrUnauthorized indicates that authentication failed or is required.
	ErrUnauthorized = errors.New("unauthorized")

	// ErrForbidden indicates that the user doesn't have permission.
	ErrForbidden = errors.New("forbidden")

	// ErrInternal indicates an internal server error.
	ErrInternal = errors.New("internal error")

	// ErrTimeout indicates that an operation timed out.
	ErrTimeout = errors.New("operation timed out")

	// ErrUnavailable indicates that a service is temporarily unavailable.
	ErrUnavailable = errors.New("service unavailable")
)

// DomainError represents an error that occurred in the domain layer.
// It provides rich error information while maintaining domain isolation.
type DomainError struct {
	// Code is a machine-readable error code.
	Code string
	// Message is a human-readable error message.
	Message string
	// Cause is the underlying error, if any.
	Cause error
	// Details contains additional error context.
	Details map[string]interface{}
}

// Error implements the error interface.
func (e *DomainError) Error() string {
	if e.Cause != nil {
		return fmt.Sprintf("%s: %s: %v", e.Code, e.Message, e.Cause)
	}
	return fmt.Sprintf("%s: %s", e.Code, e.Message)
}

// Unwrap implements the errors.Unwrap interface for error chain support.
func (e *DomainError) Unwrap() error {
	return e.Cause
}

// Is implements the errors.Is interface for error comparison.
func (e *DomainError) Is(target error) bool {
	if e.Cause != nil && errors.Is(e.Cause, target) {
		return true
	}
	return false
}

// WithDetail adds a detail to the error.
func (e *DomainError) WithDetail(key string, value interface{}) *DomainError {
	if e.Details == nil {
		e.Details = make(map[string]interface{})
	}
	e.Details[key] = value
	return e
}

// NewDomainError creates a new DomainError.
func NewDomainError(code, message string, cause error) *DomainError {
	return &DomainError{
		Code:    code,
		Message: message,
		Cause:   cause,
	}
}

// Error codes for domain errors.
const (
	// Resource errors
	ErrCodeResourceNotFound      = "RESOURCE_NOT_FOUND"
	ErrCodeResourceAlreadyExists = "RESOURCE_ALREADY_EXISTS"
	ErrCodeInvalidResourceType   = "INVALID_RESOURCE_TYPE"
	ErrCodeInvalidCloudProvider  = "INVALID_CLOUD_PROVIDER"

	// Auth errors
	ErrCodeAuthFailed              = "AUTH_FAILED"
	ErrCodeUserNotFound            = "USER_NOT_FOUND"
	ErrCodeUserAlreadyExists       = "USER_ALREADY_EXISTS"
	ErrCodeInvalidCredentials      = "INVALID_CREDENTIALS"
	ErrCodeEmailNotVerified        = "EMAIL_NOT_VERIFIED"
	ErrCodeInvalidConfirmationCode = "INVALID_CONFIRMATION_CODE"

	// Validation errors
	ErrCodeValidationFailed = "VALIDATION_FAILED"
	ErrCodeInvalidEmail     = "INVALID_EMAIL"
	ErrCodeWeakPassword     = "WEAK_PASSWORD"

	// Infrastructure errors
	ErrCodeExternalService = "EXTERNAL_SERVICE_ERROR"
	ErrCodeQueueError      = "QUEUE_ERROR"
)

// ValidationError represents a field-level validation error.
type ValidationError struct {
	Field   string
	Message string
	Value   interface{}
}

func (e *ValidationError) Error() string {
	return fmt.Sprintf("%s: %s", e.Field, e.Message)
}

// ValidationErrors is a collection of validation errors.
type ValidationErrors []ValidationError

func (e ValidationErrors) Error() string {
	if len(e) == 0 {
		return "validation failed"
	}
	return fmt.Sprintf("validation failed: %d errors", len(e))
}

// NewValidationError creates a new ValidationError.
func NewValidationError(field, message string, value interface{}) ValidationError {
	return ValidationError{
		Field:   field,
		Message: message,
		Value:   value,
	}
}

// Helper functions for creating common domain errors.

// NotFound creates a not found error.
func NotFound(resource, id string) *DomainError {
	return NewDomainError(
		ErrCodeResourceNotFound,
		fmt.Sprintf("%s with id '%s' not found", resource, id),
		ErrNotFound,
	)
}

// AlreadyExists creates an already exists error.
func AlreadyExists(resource, id string) *DomainError {
	return NewDomainError(
		ErrCodeResourceAlreadyExists,
		fmt.Sprintf("%s with id '%s' already exists", resource, id),
		ErrAlreadyExists,
	)
}

// InvalidInput creates an invalid input error.
func InvalidInput(message string) *DomainError {
	return NewDomainError(
		ErrCodeValidationFailed,
		message,
		ErrInvalidInput,
	)
}

// Unauthorized creates an unauthorized error.
func Unauthorized(message string) *DomainError {
	return NewDomainError(
		ErrCodeAuthFailed,
		message,
		ErrUnauthorized,
	)
}

// Forbidden creates a forbidden error.
func Forbidden(message string) *DomainError {
	return NewDomainError(
		ErrCodeAuthFailed,
		message,
		ErrForbidden,
	)
}

// Internal creates an internal error.
func Internal(message string, cause error) *DomainError {
	return NewDomainError(
		ErrCodeExternalService,
		message,
		cause,
	)
}
