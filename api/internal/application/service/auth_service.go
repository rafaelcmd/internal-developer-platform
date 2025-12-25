package service

import (
	"context"

	"github.com/rafaelcmd/internal-developer-platform/api/internal/domain/model"
	"github.com/rafaelcmd/internal-developer-platform/api/internal/domain/ports/outbound"
)

type AuthService struct {
	authProvider outbound.AuthProvider
}

func NewAuthService(authProvider outbound.AuthProvider) *AuthService {
	return &AuthService{
		authProvider: authProvider,
	}
}

func (s *AuthService) SignUp(ctx context.Context, req model.SignUpRequest) error {
	return s.authProvider.SignUp(ctx, req.Email, req.Password)
}

func (s *AuthService) SignIn(ctx context.Context, req model.SignInRequest) (*model.AuthResponse, error) {
	return s.authProvider.SignIn(ctx, req.Email, req.Password)
}
