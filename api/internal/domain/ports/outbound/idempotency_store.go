package outbound

import (
	"context"
	"errors"
	"time"
)

// IdempotencyState models the lifecycle of a stored idempotency record.
type IdempotencyState string

const (
	IdempotencyStateInFlight  IdempotencyState = "IN_FLIGHT"
	IdempotencyStateCompleted IdempotencyState = "COMPLETED"
)

// IdempotencyRecord is the persisted snapshot of a request keyed by the client-supplied idempotency key.
type IdempotencyRecord struct {
	Key         string
	State       IdempotencyState
	RequestHash string
	StatusCode  int
	Headers     map[string]string
	Body        []byte
	CreatedAt   time.Time
	ExpiresAt   time.Time
}

// ErrIdempotencyNotFound is returned when a key has no stored record (or its TTL has elapsed).
var ErrIdempotencyNotFound = errors.New("idempotency record not found")

// IdempotencyStore is the contract every backend (Redis, in-memory, etc.) implements.
//
// Reserve must be atomic: it either creates an IN_FLIGHT record or returns the existing one.
// Complete promotes an IN_FLIGHT record to COMPLETED with the captured response.
// Release removes an IN_FLIGHT record so a future retry can succeed (used when the handler errors out
// before a response is committed).
type IdempotencyStore interface {
	Reserve(ctx context.Context, key, requestHash string, ttl time.Duration) (existing *IdempotencyRecord, created bool, err error)
	Complete(ctx context.Context, key string, statusCode int, headers map[string]string, body []byte, ttl time.Duration) error
	Release(ctx context.Context, key string) error
}
