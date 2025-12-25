package outbound

import (
	"context"
	"github.com/rafaelcmd/internal-developer-platform/api/internal/domain/model"
)

type ResourcePublisher interface {
	Publish(ctx context.Context, resource model.Resource) error
}
