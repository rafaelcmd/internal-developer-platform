package inbound

import (
	"context"

	"github.com/rafaelcmd/cloud-ops-manager/api/internal/domain/model"
)

type AuthService interface {
	SignUp(ctx context.Context, req model.SignUpRequest) error
	SignIn(ctx context.Context, req model.SignInRequest) (*model.AuthResponse, error)
}
