package http

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"io"
	"net/http"
	"time"

	"github.com/google/uuid"

	"github.com/rafaelcmd/internal-developer-platform/api/internal/domain/ports/outbound"
)

const (
	// HeaderIdempotencyKey is the client-supplied key used to deduplicate retries.
	HeaderIdempotencyKey = "X-Idempotency-Key"

	// idempotencyReplayHeader marks responses served from the idempotency cache.
	idempotencyReplayHeader = "X-Idempotent-Replay"
)

// IdempotencyMiddleware deduplicates state-changing requests using a client-supplied UUID key.
//
// First call: hashes the body, reserves the key, runs the handler, captures the response,
// and stores it. Subsequent calls within TTL replay the captured response. A different body
// for the same key returns 422; a concurrent in-flight request returns 409.
//
// The key is optional: requests without the header pass straight through. Make it required
// only at the route level if a specific endpoint needs that guarantee.
func IdempotencyMiddleware(store outbound.IdempotencyStore, ttl time.Duration) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			key := r.Header.Get(HeaderIdempotencyKey)
			if key == "" {
				next.ServeHTTP(w, r)
				return
			}

			requestID := r.Header.Get("X-Request-Id")

			if _, err := uuid.Parse(key); err != nil {
				RespondWithError(w, http.StatusBadRequest, ErrorResponse{
					Code:      ErrCodeIdempotencyKeyInvalid,
					Message:   "X-Idempotency-Key must be a valid UUID",
					RequestID: requestID,
				})
				return
			}

			body, err := io.ReadAll(r.Body)
			if err != nil {
				RespondWithError(w, http.StatusBadRequest, ErrorResponse{
					Code:      ErrCodeInvalidJSON,
					Message:   "Failed to read request body",
					RequestID: requestID,
				})
				return
			}
			_ = r.Body.Close()
			r.Body = io.NopCloser(bytes.NewReader(body))

			hash := sha256.Sum256(body)
			requestHash := hex.EncodeToString(hash[:])

			existing, created, err := store.Reserve(r.Context(), key, requestHash, ttl)
			if err != nil {
				RespondWithError(w, http.StatusInternalServerError, ErrorResponse{
					Code:      ErrCodeInternalError,
					Message:   "Idempotency store unavailable",
					RequestID: requestID,
				})
				return
			}

			if !created {
				replayCachedResponse(w, existing, requestHash, requestID)
				return
			}

			recorder := newResponseRecorder(w)
			released := false
			defer func() {
				if rec := recover(); rec != nil {
					_ = store.Release(context.Background(), key)
					released = true
					panic(rec)
				}
			}()

			next.ServeHTTP(recorder, r)

			if shouldCacheResponse(recorder.status) {
				if err := store.Complete(r.Context(), key, recorder.status, recorder.capturedHeaders(), recorder.body.Bytes(), ttl); err != nil {
					// Completion failed but response is already on the wire — log via header for traceability.
					recorder.Header().Set("X-Idempotent-Cache", "store-failed")
				}
			} else if !released {
				_ = store.Release(context.Background(), key)
			}
		})
	}
}

// replayCachedResponse re-emits a previously stored response or returns an error when the request conflicts.
func replayCachedResponse(w http.ResponseWriter, existing *outbound.IdempotencyRecord, requestHash, requestID string) {
	if existing == nil {
		RespondWithError(w, http.StatusInternalServerError, ErrorResponse{
			Code:      ErrCodeInternalError,
			Message:   "Idempotency record missing after reservation conflict",
			RequestID: requestID,
		})
		return
	}

	if existing.RequestHash != requestHash {
		RespondWithError(w, http.StatusUnprocessableEntity, ErrorResponse{
			Code:      ErrCodeIdempotencyKeyMismatch,
			Message:   "Idempotency key was reused with a different request body",
			RequestID: requestID,
		})
		return
	}

	if existing.State == outbound.IdempotencyStateInFlight {
		w.Header().Set("Retry-After", "1")
		RespondWithError(w, http.StatusConflict, ErrorResponse{
			Code:      ErrCodeIdempotencyInProgress,
			Message:   "A request with this idempotency key is still being processed",
			RequestID: requestID,
		})
		return
	}

	for k, v := range existing.Headers {
		w.Header().Set(k, v)
	}
	w.Header().Set(idempotencyReplayHeader, "true")
	status := existing.StatusCode
	if status == 0 {
		status = http.StatusOK
	}
	w.WriteHeader(status)
	if len(existing.Body) > 0 {
		_, _ = w.Write(existing.Body)
	}
}

// shouldCacheResponse decides whether a response is worth replaying. We skip 5xx so
// transient backend errors (SQS publish failure, etc.) don't get pinned for 24h.
func shouldCacheResponse(status int) bool {
	if status == 0 {
		status = http.StatusOK
	}
	return status < 500
}

// responseRecorder buffers the handler's response so it can be both written to the
// client and persisted into the idempotency store.
type responseRecorder struct {
	http.ResponseWriter
	status      int
	body        bytes.Buffer
	wroteHeader bool
}

func newResponseRecorder(w http.ResponseWriter) *responseRecorder {
	return &responseRecorder{ResponseWriter: w, status: http.StatusOK}
}

func (r *responseRecorder) WriteHeader(status int) {
	if r.wroteHeader {
		return
	}
	r.status = status
	r.wroteHeader = true
	r.ResponseWriter.WriteHeader(status)
}

func (r *responseRecorder) Write(b []byte) (int, error) {
	if !r.wroteHeader {
		r.WriteHeader(http.StatusOK)
	}
	r.body.Write(b)
	return r.ResponseWriter.Write(b)
}

// capturedHeaders returns the subset of response headers worth replaying. We deliberately
// drop hop-by-hop and per-request headers (Date, request-id) so the replay carries the
// original payload but is timestamped/traced as the *current* request.
func (r *responseRecorder) capturedHeaders() map[string]string {
	skip := map[string]struct{}{
		"Date":              {},
		"X-Request-Id":      {},
		"X-Response-Time":   {},
		"Content-Length":    {},
		"Transfer-Encoding": {},
		"Connection":        {},
	}
	out := make(map[string]string)
	for k, v := range r.ResponseWriter.Header() {
		if _, drop := skip[k]; drop {
			continue
		}
		if len(v) > 0 {
			out[k] = v[0]
		}
	}
	return out
}

