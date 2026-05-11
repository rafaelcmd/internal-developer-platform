// Package idempotency provides storage adapters for the IdempotencyStore port.
package idempotency

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/rafaelcmd/internal-developer-platform/api/internal/domain/ports/outbound"
)

// keyPrefix scopes idempotency keys so they don't collide with other Redis tenants.
const keyPrefix = "idempotency:"

// RedisStore implements outbound.IdempotencyStore on top of Redis.
//
// Reservation atomicity comes from SET NX. Completion uses a Lua script so the
// COMPLETED record only overwrites an IN_FLIGHT record we still own.
type RedisStore struct {
	client redis.UniversalClient
}

var _ outbound.IdempotencyStore = (*RedisStore)(nil)

// NewRedisStore wraps an existing Redis client.
func NewRedisStore(client redis.UniversalClient) *RedisStore {
	return &RedisStore{client: client}
}

type recordEnvelope struct {
	State       outbound.IdempotencyState `json:"state"`
	RequestHash string                    `json:"request_hash"`
	StatusCode  int                       `json:"status_code,omitempty"`
	Headers     map[string]string         `json:"headers,omitempty"`
	Body        []byte                    `json:"body,omitempty"`
	CreatedAt   time.Time                 `json:"created_at"`
	ExpiresAt   time.Time                 `json:"expires_at"`
}

// Reserve atomically inserts an IN_FLIGHT record for `key`. If the key already exists,
// it returns the existing record with created=false.
func (s *RedisStore) Reserve(ctx context.Context, key, requestHash string, ttl time.Duration) (*outbound.IdempotencyRecord, bool, error) {
	now := time.Now().UTC()
	env := recordEnvelope{
		State:       outbound.IdempotencyStateInFlight,
		RequestHash: requestHash,
		CreatedAt:   now,
		ExpiresAt:   now.Add(ttl),
	}
	payload, err := json.Marshal(env)
	if err != nil {
		return nil, false, fmt.Errorf("marshal idempotency reservation: %w", err)
	}

	ok, err := s.client.SetNX(ctx, keyPrefix+key, payload, ttl).Result()
	if err != nil {
		return nil, false, fmt.Errorf("redis SETNX: %w", err)
	}
	if ok {
		return &outbound.IdempotencyRecord{
			Key:         key,
			State:       env.State,
			RequestHash: env.RequestHash,
			CreatedAt:   env.CreatedAt,
			ExpiresAt:   env.ExpiresAt,
		}, true, nil
	}

	existing, err := s.get(ctx, key)
	if err != nil {
		return nil, false, err
	}
	return existing, false, nil
}

// completeScript replaces the value only if it currently exists, sets a fresh TTL, and is no-op if missing.
// We don't compare-and-set on the in-flight payload because the caller has already proven ownership
// (it received created=true from Reserve and is the only goroutine wrapping the handler for that key).
var completeScript = redis.NewScript(`
if redis.call("EXISTS", KEYS[1]) == 0 then
  return 0
end
redis.call("SET", KEYS[1], ARGV[1], "PX", ARGV[2])
return 1
`)

// Complete persists the final response under `key`. Caller must have observed created=true in Reserve.
func (s *RedisStore) Complete(ctx context.Context, key string, statusCode int, headers map[string]string, body []byte, ttl time.Duration) error {
	now := time.Now().UTC()
	existing, err := s.get(ctx, key)
	if err != nil {
		if errors.Is(err, outbound.ErrIdempotencyNotFound) {
			return nil
		}
		return err
	}

	env := recordEnvelope{
		State:       outbound.IdempotencyStateCompleted,
		RequestHash: existing.RequestHash,
		StatusCode:  statusCode,
		Headers:     headers,
		Body:        body,
		CreatedAt:   existing.CreatedAt,
		ExpiresAt:   now.Add(ttl),
	}
	payload, err := json.Marshal(env)
	if err != nil {
		return fmt.Errorf("marshal idempotency completion: %w", err)
	}

	if _, err := completeScript.Run(ctx, s.client, []string{keyPrefix + key}, payload, ttl.Milliseconds()).Result(); err != nil {
		return fmt.Errorf("redis complete script: %w", err)
	}
	return nil
}

// Release removes the IN_FLIGHT slot. If the record was already promoted to COMPLETED
// (race with another goroutine) we leave it alone — that response is the truth.
var releaseScript = redis.NewScript(`
local raw = redis.call("GET", KEYS[1])
if raw == false then
  return 0
end
if string.find(raw, '"IN_FLIGHT"', 1, true) then
  redis.call("DEL", KEYS[1])
  return 1
end
return 0
`)

func (s *RedisStore) Release(ctx context.Context, key string) error {
	if _, err := releaseScript.Run(ctx, s.client, []string{keyPrefix + key}).Result(); err != nil {
		return fmt.Errorf("redis release script: %w", err)
	}
	return nil
}

func (s *RedisStore) get(ctx context.Context, key string) (*outbound.IdempotencyRecord, error) {
	raw, err := s.client.Get(ctx, keyPrefix+key).Bytes()
	if err != nil {
		if errors.Is(err, redis.Nil) {
			return nil, outbound.ErrIdempotencyNotFound
		}
		return nil, fmt.Errorf("redis GET: %w", err)
	}

	var env recordEnvelope
	if err := json.Unmarshal(raw, &env); err != nil {
		return nil, fmt.Errorf("unmarshal idempotency record: %w", err)
	}

	return &outbound.IdempotencyRecord{
		Key:         key,
		State:       env.State,
		RequestHash: env.RequestHash,
		StatusCode:  env.StatusCode,
		Headers:     env.Headers,
		Body:        env.Body,
		CreatedAt:   env.CreatedAt,
		ExpiresAt:   env.ExpiresAt,
	}, nil
}
