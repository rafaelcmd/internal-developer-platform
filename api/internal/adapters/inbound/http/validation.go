package http

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"

	"github.com/go-playground/validator/v10"
)

// =============================================================================
// VALIDATION ERROR RESPONSE
// Standardized error response structure for validation failures (DVA-C02 best practice)
// =============================================================================

// ValidationError represents a single field validation error
type ValidationError struct {
	Field   string `json:"field"`
	Message string `json:"message"`
	Value   any    `json:"value,omitempty"`
}

// ErrorResponse represents a standardized API error response
// This structure follows DVA-C02 best practices for consistent error handling
type ErrorResponse struct {
	Code      string            `json:"code"`
	Message   string            `json:"message"`
	RequestID string            `json:"requestId,omitempty"`
	Details   []ValidationError `json:"details,omitempty"`
}

// Common error codes
const (
	ErrCodeValidation    = "VALIDATION_ERROR"
	ErrCodeInvalidJSON   = "INVALID_JSON"
	ErrCodeMissingHeader = "MISSING_HEADER"
	ErrCodeInternalError = "INTERNAL_ERROR"
	ErrCodeUnauthorized  = "UNAUTHORIZED"
	ErrCodeNotFound      = "NOT_FOUND"
	ErrCodeRateLimited   = "RATE_LIMITED"
)

// =============================================================================
// VALIDATOR SINGLETON
// Thread-safe validator instance for request validation
// =============================================================================

var validate *validator.Validate

func init() {
	validate = validator.New(validator.WithRequiredStructEnabled())

	// Register custom validation tags if needed
	// Example: validate.RegisterValidation("custom_tag", customValidationFunc)
}

// GetValidator returns the singleton validator instance
func GetValidator() *validator.Validate {
	return validate
}

// =============================================================================
// VALIDATION HELPER FUNCTIONS
// =============================================================================

// ValidateStruct validates a struct and returns a slice of ValidationError
func ValidateStruct(s any) []ValidationError {
	err := validate.Struct(s)
	if err == nil {
		return nil
	}

	var errors []ValidationError
	for _, err := range err.(validator.ValidationErrors) {
		errors = append(errors, ValidationError{
			Field:   toSnakeCase(err.Field()),
			Message: formatValidationMessage(err),
			Value:   err.Value(),
		})
	}
	return errors
}

// formatValidationMessage creates a human-readable validation error message
func formatValidationMessage(fe validator.FieldError) string {
	field := toSnakeCase(fe.Field())

	switch fe.Tag() {
	case "required":
		return fmt.Sprintf("%s is required", field)
	case "email":
		return fmt.Sprintf("%s must be a valid email address", field)
	case "min":
		return fmt.Sprintf("%s must be at least %s characters", field, fe.Param())
	case "max":
		return fmt.Sprintf("%s must be at most %s characters", field, fe.Param())
	case "oneof":
		return fmt.Sprintf("%s must be one of: %s", field, fe.Param())
	case "url":
		return fmt.Sprintf("%s must be a valid URL", field)
	case "uuid":
		return fmt.Sprintf("%s must be a valid UUID", field)
	case "alphanum":
		return fmt.Sprintf("%s must contain only alphanumeric characters", field)
	case "gte":
		return fmt.Sprintf("%s must be greater than or equal to %s", field, fe.Param())
	case "lte":
		return fmt.Sprintf("%s must be less than or equal to %s", field, fe.Param())
	default:
		return fmt.Sprintf("%s failed validation: %s", field, fe.Tag())
	}
}

// toSnakeCase converts PascalCase/camelCase to snake_case
func toSnakeCase(s string) string {
	var result strings.Builder
	for i, r := range s {
		if i > 0 && r >= 'A' && r <= 'Z' {
			result.WriteRune('_')
		}
		result.WriteRune(r)
	}
	return strings.ToLower(result.String())
}

// =============================================================================
// HTTP RESPONSE HELPERS
// =============================================================================

// RespondWithError sends a standardized JSON error response
func RespondWithError(w http.ResponseWriter, statusCode int, errResp ErrorResponse) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	json.NewEncoder(w).Encode(errResp)
}

// RespondWithValidationError sends a 400 response with validation errors
func RespondWithValidationError(w http.ResponseWriter, requestID string, errors []ValidationError) {
	RespondWithError(w, http.StatusBadRequest, ErrorResponse{
		Code:      ErrCodeValidation,
		Message:   "Request validation failed",
		RequestID: requestID,
		Details:   errors,
	})
}

// RespondWithJSON sends a JSON response with the given status code
func RespondWithJSON(w http.ResponseWriter, statusCode int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	if payload != nil {
		json.NewEncoder(w).Encode(payload)
	}
}

// =============================================================================
// REQUEST PARSING AND VALIDATION
// =============================================================================

// DecodeAndValidate decodes JSON body and validates the struct
// Returns the decoded struct or writes error response and returns nil
func DecodeAndValidate[T any](w http.ResponseWriter, r *http.Request, requestID string) *T {
	var payload T

	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		RespondWithError(w, http.StatusBadRequest, ErrorResponse{
			Code:      ErrCodeInvalidJSON,
			Message:   "Invalid JSON in request body",
			RequestID: requestID,
		})
		return nil
	}

	if errors := ValidateStruct(payload); len(errors) > 0 {
		RespondWithValidationError(w, requestID, errors)
		return nil
	}

	return &payload
}

// ValidateRequiredHeader checks if a required header is present
func ValidateRequiredHeader(w http.ResponseWriter, r *http.Request, headerName, requestID string) bool {
	if r.Header.Get(headerName) == "" {
		RespondWithError(w, http.StatusBadRequest, ErrorResponse{
			Code:      ErrCodeMissingHeader,
			Message:   fmt.Sprintf("Missing required header: %s", headerName),
			RequestID: requestID,
			Details: []ValidationError{
				{
					Field:   headerName,
					Message: fmt.Sprintf("Header '%s' is required", headerName),
				},
			},
		})
		return false
	}
	return true
}
