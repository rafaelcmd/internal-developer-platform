package idempotency

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/rafaelcmd/internal-developer-platform/api/internal/domain/ports/outbound"
)

// redisAddrFromEnv returns the test Redis address, or skips the test if not set.
// We don't spin up Redis for unit tests — set REDIS_TEST_ADDR=localhost:6379 (e.g. via
// the docker-compose redis service) to exercise the real implementation.
func redisAddrFromEnv(t *testing.T) string {
	t.Helper()
	addr := os.Getenv("REDIS_TEST_ADDR")
	if addr == "" {
		t.Skip("REDIS_TEST_ADDR not set; skipping Redis integration test")
	}
	return addr
}

func newTestStore(t *testing.T) (*RedisStore, *redis.Client) {
	t.Helper()
	client := redis.NewClient(&redis.Options{Addr: redisAddrFromEnv(t)})
	t.Cleanup(func() { _ = client.Close() })
	require.NoError(t, client.Ping(context.Background()).Err())
	return NewRedisStore(client), client
}

func TestRedisStore_ReserveCreatesNewRecord(t *testing.T) {
	store, _ := newTestStore(t)
	ctx := context.Background()

	key := uuid.New().String()
	existing, created, err := store.Reserve(ctx, key, "hash-a", time.Minute)

	require.NoError(t, err)
	assert.True(t, created)
	assert.NotNil(t, existing)
	assert.Equal(t, outbound.IdempotencyStateInFlight, existing.State)
	assert.Equal(t, "hash-a", existing.RequestHash)
}

func TestRedisStore_ReserveReturnsExistingOnSecondCall(t *testing.T) {
	store, _ := newTestStore(t)
	ctx := context.Background()

	key := uuid.New().String()
	_, created, err := store.Reserve(ctx, key, "hash-a", time.Minute)
	require.NoError(t, err)
	require.True(t, created)

	existing, created, err := store.Reserve(ctx, key, "hash-b", time.Minute)
	require.NoError(t, err)
	assert.False(t, created)
	require.NotNil(t, existing)
	assert.Equal(t, "hash-a", existing.RequestHash, "RequestHash from the first reservation must win")
}

func TestRedisStore_CompletePromotesRecordAndReplaysFields(t *testing.T) {
	store, _ := newTestStore(t)
	ctx := context.Background()

	key := uuid.New().String()
	_, _, err := store.Reserve(ctx, key, "hash-x", time.Minute)
	require.NoError(t, err)

	headers := map[string]string{"Content-Type": "application/json"}
	body := []byte(`{"id":"abc"}`)
	require.NoError(t, store.Complete(ctx, key, 202, headers, body, time.Minute))

	existing, created, err := store.Reserve(ctx, key, "hash-x", time.Minute)
	require.NoError(t, err)
	assert.False(t, created)
	require.NotNil(t, existing)
	assert.Equal(t, outbound.IdempotencyStateCompleted, existing.State)
	assert.Equal(t, 202, existing.StatusCode)
	assert.Equal(t, "application/json", existing.Headers["Content-Type"])
	assert.JSONEq(t, `{"id":"abc"}`, string(existing.Body))
}

func TestRedisStore_ReleaseRemovesInFlightRecord(t *testing.T) {
	store, client := newTestStore(t)
	ctx := context.Background()

	key := uuid.New().String()
	_, _, err := store.Reserve(ctx, key, "hash-x", time.Minute)
	require.NoError(t, err)

	require.NoError(t, store.Release(ctx, key))

	exists, err := client.Exists(ctx, keyPrefix+key).Result()
	require.NoError(t, err)
	assert.Equal(t, int64(0), exists, "release must delete the in-flight key")
}

func TestRedisStore_ReleaseDoesNotRemoveCompletedRecord(t *testing.T) {
	store, client := newTestStore(t)
	ctx := context.Background()

	key := uuid.New().String()
	_, _, err := store.Reserve(ctx, key, "hash-x", time.Minute)
	require.NoError(t, err)
	require.NoError(t, store.Complete(ctx, key, 200, nil, []byte(`{}`), time.Minute))

	require.NoError(t, store.Release(ctx, key))

	exists, err := client.Exists(ctx, keyPrefix+key).Result()
	require.NoError(t, err)
	assert.Equal(t, int64(1), exists, "release must leave a completed record alone")
}
