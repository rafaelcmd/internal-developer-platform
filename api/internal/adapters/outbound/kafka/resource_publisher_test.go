package kafka

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/rafaelcmd/internal-developer-platform/api/internal/domain/model"
)

func TestPublish_UnreachableBroker_ReturnsError(t *testing.T) {
	p := NewResourcePublisher([]string{"127.0.0.1:1"}, "test-topic")
	defer p.Close()

	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()

	err := p.Publish(ctx, model.Resource{ID: "vm-1", ResourceType: "VM"})
	require.Error(t, err, "publishing to an unreachable broker must error")
}

func TestClose_IsSafe(t *testing.T) {
	p := NewResourcePublisher([]string{"127.0.0.1:9092"}, "test-topic")
	assert.NoError(t, p.Close())
}
