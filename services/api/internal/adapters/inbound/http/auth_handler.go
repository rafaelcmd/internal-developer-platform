package http

import (
	"net/http"

	"github.com/rafaelcmd/internal-developer-platform/api/internal/domain/model"
	"github.com/rafaelcmd/internal-developer-platform/api/internal/domain/ports/inbound"
	"github.com/rafaelcmd/internal-developer-platform/api/internal/logger"
)

type AuthHandler struct {
	authService inbound.AuthService
	logger      logger.Logger
}

func NewAuthHandler(authService inbound.AuthService, log logger.Logger) *AuthHandler {
	return &AuthHandler{
		authService: authService,
		logger:      log.WithField("component", "auth_handler"),
	}
}

// getRequestID extracts request ID from headers or generates one
func getRequestID(r *http.Request) string {
	if id := r.Header.Get("X-Request-Id"); id != "" {
		return id
	}
	if id := r.Header.Get("X-Amzn-Trace-Id"); id != "" {
		return id
	}
	return ""
}

// SignUp handles user registration requests.
func (h *AuthHandler) SignUp(w http.ResponseWriter, r *http.Request) {
	requestID := getRequestID(r)

	// Decode and validate request body
	req := DecodeAndValidate[model.SignUpRequest](w, r, requestID)
	if req == nil {
		return // Response already sent by DecodeAndValidate
	}

	if err := h.authService.SignUp(r.Context(), *req); err != nil {
		h.logger.WithError(err).Error("auth.signup: service error")
		RespondWithError(w, http.StatusInternalServerError, ErrorResponse{
			Code:      ErrCodeInternalError,
			Message:   "Failed to create user",
			RequestID: requestID,
		})
		return
	}

	h.logger.WithField("email", req.Email).Info("auth.signup: user created")
	RespondWithJSON(w, http.StatusCreated, NewAPIResponse(CreatedResponse{
		Message: "User created successfully",
		Status:  "CREATED",
	}, requestID))
}

// SignIn handles user authentication and returns tokens.
func (h *AuthHandler) SignIn(w http.ResponseWriter, r *http.Request) {
	requestID := getRequestID(r)

	// Decode and validate request body
	req := DecodeAndValidate[model.SignInRequest](w, r, requestID)
	if req == nil {
		return // Response already sent by DecodeAndValidate
	}

	resp, err := h.authService.SignIn(r.Context(), *req)
	if err != nil {
		h.logger.WithError(err).Warn("auth.signin: unauthorized")
		RespondWithError(w, http.StatusUnauthorized, ErrorResponse{
			Code:      ErrCodeUnauthorized,
			Message:   "Invalid credentials",
			RequestID: requestID,
		})
		return
	}

	h.logger.WithField("email", req.Email).Info("auth.signin: user authenticated")
	RespondWithJSON(w, http.StatusOK, NewAPIResponse(resp, requestID))
}

// ConfirmSignUp handles sign-up confirmation using the code sent by email.
func (h *AuthHandler) ConfirmSignUp(w http.ResponseWriter, r *http.Request) {
	requestID := getRequestID(r)

	// Decode and validate request body
	req := DecodeAndValidate[model.ConfirmSignUpRequest](w, r, requestID)
	if req == nil {
		return // Response already sent by DecodeAndValidate
	}

	if err := h.authService.ConfirmSignUp(r.Context(), *req); err != nil {
		h.logger.WithError(err).Error("auth.confirm: service error")
		RespondWithError(w, http.StatusInternalServerError, ErrorResponse{
			Code:      ErrCodeInternalError,
			Message:   "Failed to confirm user",
			RequestID: requestID,
		})
		return
	}

	h.logger.WithField("email", req.Email).Info("auth.confirm: user confirmed")
	RespondWithJSON(w, http.StatusOK, NewAPIResponse(MessageResponse{
		Message: "User confirmed successfully",
		Status:  "CONFIRMED",
	}, requestID))
}
