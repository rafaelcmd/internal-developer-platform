package http

import (
	"net/http"

	"github.com/rafaelcmd/internal-developer-platform/api/internal/domain/model"
	"github.com/rafaelcmd/internal-developer-platform/api/internal/domain/ports/inbound"
	"github.com/sirupsen/logrus"
)

type AuthHandler struct {
	authService inbound.AuthService
	logger      *logrus.Entry
}

func NewAuthHandler(authService inbound.AuthService, logger *logrus.Entry) *AuthHandler {
	return &AuthHandler{
		authService: authService,
		logger:      logger,
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

// SignUp godoc
// @Summary Sign up a new user
// @Description Registers a new user with email and password
// @Tags auth
// @Accept json
// @Produce json
// @Param request body model.SignUpRequest true "Sign up request"
// @Success 201 {object} APIResponse[CreatedResponse] "User created successfully"
// @Failure 400 {object} ErrorResponse "Validation error"
// @Failure 500 {object} ErrorResponse "Internal server error"
// @Router /v1/auth/signup [post]
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

// SignIn godoc
// @Summary Sign in
// @Description Authenticates a user and returns tokens
// @Tags auth
// @Accept json
// @Produce json
// @Param request body model.SignInRequest true "Sign in request"
// @Success 200 {object} APIResponse[model.AuthResponse] "Authentication successful"
// @Failure 400 {object} ErrorResponse "Validation error"
// @Failure 401 {object} ErrorResponse "Unauthorized"
// @Failure 500 {object} ErrorResponse "Internal server error"
// @Router /v1/auth/signin [post]
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

// ConfirmSignUp godoc
// @Summary Confirm sign up
// @Description Confirms a user's sign up using the code sent by email
// @Tags auth
// @Accept json
// @Produce json
// @Param request body model.ConfirmSignUpRequest true "Confirm sign up request"
// @Success 200 {object} APIResponse[MessageResponse] "User confirmed successfully"
// @Failure 400 {object} ErrorResponse "Validation error"
// @Failure 500 {object} ErrorResponse "Internal server error"
// @Router /v1/auth/confirm [post]
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
