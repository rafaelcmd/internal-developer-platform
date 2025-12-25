package outbound

import (
	"context"

	"github.com/rafaelcmd/internal-developer-platform/api/internal/domain/model"
)

type AuthProvider interface {
	SignUp(ctx context.Context, email, password string) error
	SignIn(ctx context.Context, email, password string) (*model.AuthResponse, error)
}
