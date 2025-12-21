package http

import (
	"encoding/json"
	"net/http"

	"github.com/rafaelcmd/cloud-ops-manager/api/internal/domain/model"
	"github.com/rafaelcmd/cloud-ops-manager/api/internal/domain/ports/inbound"
)

type AuthHandler struct {
	authService inbound.AuthService
}

func NewAuthHandler(authService inbound.AuthService) *AuthHandler {
	return &AuthHandler{
		authService: authService,
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
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if err := h.authService.SignUp(r.Context(), req); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

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
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	resp, err := h.authService.SignIn(r.Context(), req)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}
