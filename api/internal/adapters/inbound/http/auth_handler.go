package http

import (
	"encoding/json"
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

// SignUp godoc
// @Summary Sign up a new user
// @Description Registers a new user with email and password
// @Tags auth
// @Accept json
// @Produce json
// @Param request body model.SignUpRequest true "Sign up request"
// @Success 201 {string} string "User created successfully"
// @Failure 400 {string} string "Invalid request"
// @Failure 500 {string} string "Internal server error"
// @Router /auth/signup [post]
func (h *AuthHandler) SignUp(w http.ResponseWriter, r *http.Request) {
	var req model.SignUpRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.logger.WithError(err).Warn("auth.signup: failed to decode request")
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if err := h.authService.SignUp(r.Context(), req); err != nil {
		h.logger.WithError(err).Error("auth.signup: service error")
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	h.logger.WithField("email", req.Email).Info("auth.signup: user created")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]string{"message": "User created successfully"})
}

// SignIn godoc
// @Summary Sign in
// @Description Authenticates a user and returns tokens
// @Tags auth
// @Accept json
// @Produce json
// @Param request body model.SignInRequest true "Sign in request"
// @Success 200 {object} model.AuthResponse
// @Failure 400 {string} string "Invalid request"
// @Failure 401 {string} string "Unauthorized"
// @Failure 500 {string} string "Internal server error"
// @Router /auth/signin [post]
func (h *AuthHandler) SignIn(w http.ResponseWriter, r *http.Request) {
	var req model.SignInRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.logger.WithError(err).Warn("auth.signin: failed to decode request")
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	resp, err := h.authService.SignIn(r.Context(), req)
	if err != nil {
		h.logger.WithError(err).Warn("auth.signin: unauthorized")
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}

	h.logger.WithField("email", req.Email).Info("auth.signin: user authenticated")
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

// ConfirmSignUp godoc
// @Summary Confirm sign up
// @Description Confirms a user's sign up using the code sent by email
// @Tags auth
// @Accept json
// @Produce json
// @Param request body model.ConfirmSignUpRequest true "Confirm sign up request"
// @Success 200 {string} string "User confirmed successfully"
// @Failure 400 {string} string "Invalid request"
// @Failure 500 {string} string "Internal server error"
// @Router /auth/confirm [post]
func (h *AuthHandler) ConfirmSignUp(w http.ResponseWriter, r *http.Request) {
	var req model.ConfirmSignUpRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.logger.WithError(err).Warn("auth.confirm: failed to decode request")
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if err := h.authService.ConfirmSignUp(r.Context(), req); err != nil {
		h.logger.WithError(err).Error("auth.confirm: service error")
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	h.logger.WithField("email", req.Email).Info("auth.confirm: user confirmed")
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"message": "User confirmed successfully"})
}
