package http

import (
	"bytes"
	"context"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/rafaelcmd/internal-developer-platform/api/internal/domain/ports/outbound"
)

// fakeStore is an in-memory test double for outbound.IdempotencyStore.
// It exists only here so middleware unit tests don't need a real Redis.
type fakeStore struct {
	mu          sync.Mutex
	records     map[string]*outbound.IdempotencyRecord
	reserveErr  error
	completeErr error
}

func newFakeStore() *fakeStore {
	return &fakeStore{records: make(map[string]*outbound.IdempotencyRecord)}
}

func (s *fakeStore) Reserve(_ context.Context, key, hash string, ttl time.Duration) (*outbound.IdempotencyRecord, bool, error) {
	if s.reserveErr != nil {
		return nil, false, s.reserveErr
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if existing, ok := s.records[key]; ok {
		copy := *existing
		return &copy, false, nil
	}
	rec := &outbound.IdempotencyRecord{
		Key:         key,
		State:       outbound.IdempotencyStateInFlight,
		RequestHash: hash,
		CreatedAt:   time.Now(),
		ExpiresAt:   time.Now().Add(ttl),
	}
	s.records[key] = rec
	return rec, true, nil
}

func (s *fakeStore) Complete(_ context.Context, key string, status int, headers map[string]string, body []byte, ttl time.Duration) error {
	if s.completeErr != nil {
		return s.completeErr
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	rec, ok := s.records[key]
	if !ok {
		return errors.New("not reserved")
	}
	rec.State = outbound.IdempotencyStateCompleted
	rec.StatusCode = status
	rec.Headers = headers
	rec.Body = append([]byte(nil), body...)
	rec.ExpiresAt = time.Now().Add(ttl)
	return nil
}

func (s *fakeStore) Release(_ context.Context, key string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.records, key)
	return nil
}

func newRequest(t *testing.T, key, body string) *http.Request {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/v1/provision", bytes.NewBufferString(body))
	if key != "" {
		req.Header.Set(HeaderIdempotencyKey, key)
	}
	return req
}

func okHandler(status int, body string) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// drain body to mimic real handlers
		_, _ = io.Copy(io.Discard, r.Body)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(status)
		_, _ = w.Write([]byte(body))
	})
}

func TestIdempotencyMiddleware_NoHeaderPassesThrough(t *testing.T) {
	store := newFakeStore()
	called := false
	mw := IdempotencyMiddleware(store, time.Hour)
	h := mw(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		called = true
		w.WriteHeader(http.StatusAccepted)
	}))

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, newRequest(t, "", `{"x":1}`))

	assert.True(t, called)
	assert.Equal(t, http.StatusAccepted, rec.Code)
	assert.Empty(t, store.records, "no key should be stored when header is absent")
}

func TestIdempotencyMiddleware_InvalidUUIDReturns400(t *testing.T) {
	store := newFakeStore()
	mw := IdempotencyMiddleware(store, time.Hour)
	h := mw(okHandler(http.StatusAccepted, `{"ok":true}`))

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, newRequest(t, "not-a-uuid", `{}`))

	assert.Equal(t, http.StatusBadRequest, rec.Code)
	assert.Contains(t, rec.Body.String(), ErrCodeIdempotencyKeyInvalid)
}

func TestIdempotencyMiddleware_FirstCallReachesHandlerAndStoresResponse(t *testing.T) {
	store := newFakeStore()
	mw := IdempotencyMiddleware(store, time.Hour)
	h := mw(okHandler(http.StatusAccepted, `{"id":"abc"}`))

	key := uuid.New().String()
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, newRequest(t, key, `{"x":1}`))

	require.Equal(t, http.StatusAccepted, rec.Code)
	require.Contains(t, store.records, key)
	stored := store.records[key]
	assert.Equal(t, outbound.IdempotencyStateCompleted, stored.State)
	assert.Equal(t, http.StatusAccepted, stored.StatusCode)
	assert.JSONEq(t, `{"id":"abc"}`, string(stored.Body))
}

func TestIdempotencyMiddleware_DuplicateReplaysCachedResponse(t *testing.T) {
	store := newFakeStore()
	mw := IdempotencyMiddleware(store, time.Hour)

	key := uuid.New().String()
	calls := 0
	h := mw(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusAccepted)
		_, _ = w.Write([]byte(`{"id":"first"}`))
	}))

	rec1 := httptest.NewRecorder()
	h.ServeHTTP(rec1, newRequest(t, key, `{"x":1}`))
	require.Equal(t, http.StatusAccepted, rec1.Code)

	rec2 := httptest.NewRecorder()
	h.ServeHTTP(rec2, newRequest(t, key, `{"x":1}`))

	assert.Equal(t, 1, calls, "handler must only run once")
	assert.Equal(t, http.StatusAccepted, rec2.Code)
	assert.JSONEq(t, `{"id":"first"}`, rec2.Body.String())
	assert.Equal(t, "true", rec2.Header().Get("X-Idempotent-Replay"))
}

func TestIdempotencyMiddleware_SameKeyDifferentBodyReturns422(t *testing.T) {
	store := newFakeStore()
	mw := IdempotencyMiddleware(store, time.Hour)
	h := mw(okHandler(http.StatusAccepted, `{"ok":true}`))

	key := uuid.New().String()
	rec1 := httptest.NewRecorder()
	h.ServeHTTP(rec1, newRequest(t, key, `{"x":1}`))
	require.Equal(t, http.StatusAccepted, rec1.Code)

	rec2 := httptest.NewRecorder()
	h.ServeHTTP(rec2, newRequest(t, key, `{"x":2}`))

	assert.Equal(t, http.StatusUnprocessableEntity, rec2.Code)
	assert.Contains(t, rec2.Body.String(), ErrCodeIdempotencyKeyMismatch)
}

func TestIdempotencyMiddleware_InFlightReturns409(t *testing.T) {
	store := newFakeStore()
	mw := IdempotencyMiddleware(store, time.Hour)

	// Pre-seed an IN_FLIGHT record for `key` with a matching hash so the second request
	// hits the in-flight branch rather than the mismatch branch.
	key := uuid.New().String()
	body := `{"x":1}`
	rec0 := httptest.NewRecorder()
	mw(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Reserve happens before this handler runs; mutate the stored record in place
		// to simulate a still-in-flight request.
		store.mu.Lock()
		store.records[key].State = outbound.IdempotencyStateInFlight
		store.mu.Unlock()
		// don't call WriteHeader so the recorder captures the default
	})).ServeHTTP(rec0, newRequest(t, key, body))
	// rec0 isn't asserted; we only care about the seeded state.
	store.mu.Lock()
	store.records[key].State = outbound.IdempotencyStateInFlight
	store.mu.Unlock()

	rec := httptest.NewRecorder()
	mw(okHandler(http.StatusAccepted, `{"ok":true}`)).ServeHTTP(rec, newRequest(t, key, body))

	assert.Equal(t, http.StatusConflict, rec.Code)
	assert.Contains(t, rec.Body.String(), ErrCodeIdempotencyInProgress)
}

func TestIdempotencyMiddleware_HandlerErrorReleasesReservation(t *testing.T) {
	store := newFakeStore()
	mw := IdempotencyMiddleware(store, time.Hour)
	h := mw(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))

	key := uuid.New().String()
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, newRequest(t, key, `{"x":1}`))

	assert.Equal(t, http.StatusInternalServerError, rec.Code)
	store.mu.Lock()
	defer store.mu.Unlock()
	_, exists := store.records[key]
	assert.False(t, exists, "5xx responses must release the reservation so retries can succeed")
}

func TestIdempotencyMiddleware_StoreFailureReturns500(t *testing.T) {
	store := newFakeStore()
	store.reserveErr = errors.New("redis down")
	mw := IdempotencyMiddleware(store, time.Hour)
	h := mw(okHandler(http.StatusAccepted, `{}`))

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, newRequest(t, uuid.New().String(), `{}`))

	assert.Equal(t, http.StatusInternalServerError, rec.Code)
	assert.Contains(t, rec.Body.String(), "Idempotency store unavailable")
}
