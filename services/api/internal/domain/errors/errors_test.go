package errors

import (
	"errors"
	"testing"
)

func TestDomainError_Error(t *testing.T) {
	tests := []struct {
		name     string
		err      *DomainError
		expected string
	}{
		{
			name: "with cause",
			err: &DomainError{
				Code:    "TEST_ERROR",
				Message: "test message",
				Cause:   errors.New("underlying error"),
			},
			expected: "TEST_ERROR: test message: underlying error",
		},
		{
			name: "without cause",
			err: &DomainError{
				Code:    "TEST_ERROR",
				Message: "test message",
			},
			expected: "TEST_ERROR: test message",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := tt.err.Error(); got != tt.expected {
				t.Errorf("DomainError.Error() = %v, want %v", got, tt.expected)
			}
		})
	}
}

func TestDomainError_Unwrap(t *testing.T) {
	cause := errors.New("underlying error")
	err := &DomainError{
		Code:    "TEST_ERROR",
		Message: "test message",
		Cause:   cause,
	}

	if unwrapped := err.Unwrap(); unwrapped != cause {
		t.Errorf("DomainError.Unwrap() = %v, want %v", unwrapped, cause)
	}
}

func TestDomainError_Is(t *testing.T) {
	err := &DomainError{
		Code:    "TEST_ERROR",
		Message: "test message",
		Cause:   ErrNotFound,
	}

	if !err.Is(ErrNotFound) {
		t.Error("DomainError.Is(ErrNotFound) should return true")
	}

	if err.Is(ErrUnauthorized) {
		t.Error("DomainError.Is(ErrUnauthorized) should return false")
	}
}

func TestDomainError_WithDetail(t *testing.T) {
	err := NewDomainError("TEST", "test", nil)
	err.WithDetail("key1", "value1")
	err.WithDetail("key2", 123)

	if err.Details["key1"] != "value1" {
		t.Errorf("expected detail key1 to be value1, got %v", err.Details["key1"])
	}
	if err.Details["key2"] != 123 {
		t.Errorf("expected detail key2 to be 123, got %v", err.Details["key2"])
	}
}

func TestNotFound(t *testing.T) {
	err := NotFound("User", "123")

	if err.Code != ErrCodeResourceNotFound {
		t.Errorf("expected code %s, got %s", ErrCodeResourceNotFound, err.Code)
	}
	if !errors.Is(err, ErrNotFound) {
		t.Error("NotFound error should wrap ErrNotFound")
	}
}

func TestAlreadyExists(t *testing.T) {
	err := AlreadyExists("User", "123")

	if err.Code != ErrCodeResourceAlreadyExists {
		t.Errorf("expected code %s, got %s", ErrCodeResourceAlreadyExists, err.Code)
	}
	if !errors.Is(err, ErrAlreadyExists) {
		t.Error("AlreadyExists error should wrap ErrAlreadyExists")
	}
}

func TestUnauthorized(t *testing.T) {
	err := Unauthorized("access denied")

	if err.Code != ErrCodeAuthFailed {
		t.Errorf("expected code %s, got %s", ErrCodeAuthFailed, err.Code)
	}
	if !errors.Is(err, ErrUnauthorized) {
		t.Error("Unauthorized error should wrap ErrUnauthorized")
	}
}

func TestValidationErrors_Error(t *testing.T) {
	errs := ValidationErrors{
		{Field: "email", Message: "invalid email"},
		{Field: "password", Message: "too short"},
	}

	expected := "validation failed: 2 errors"
	if got := errs.Error(); got != expected {
		t.Errorf("ValidationErrors.Error() = %v, want %v", got, expected)
	}
}

func TestValidationErrors_Empty(t *testing.T) {
	errs := ValidationErrors{}

	expected := "validation failed"
	if got := errs.Error(); got != expected {
		t.Errorf("ValidationErrors.Error() = %v, want %v", got, expected)
	}
}
