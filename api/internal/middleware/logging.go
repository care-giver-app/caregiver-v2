package middleware

import (
	"log/slog"
	"net/http"
	"runtime/debug"
	"time"

	"github.com/awslabs/aws-lambda-go-api-proxy/core"
	"github.com/google/uuid"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/logger"
)

// statusRecorder captures the response status code and byte count so the access
// line can report them. Defaults to 200 until WriteHeader is called.
type statusRecorder struct {
	http.ResponseWriter
	status      int
	bytes       int
	wroteHeader bool
}

func (r *statusRecorder) WriteHeader(code int) {
	if !r.wroteHeader {
		r.status = code
		r.wroteHeader = true
	}
	r.ResponseWriter.WriteHeader(code)
}

func (r *statusRecorder) Write(b []byte) (int, error) {
	n, err := r.ResponseWriter.Write(b)
	r.bytes += n
	return n, err
}

// RequestLogger wraps the mux with: a request-scoped logger in context
// (request_id/method/path), panic recovery, and exactly one access-log line per
// request (status/duration_ms/route). It must wrap the mux so r.Pattern (Go
// 1.23) is populated by routing before the access line is emitted.
func RequestLogger(base *slog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()
			log := base.With("request_id", requestID(r), "method", r.Method, "path", r.URL.Path)
			r = r.WithContext(logger.NewContext(r.Context(), log))
			rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}

			defer func() {
				if rv := recover(); rv != nil {
					logger.FromContext(r.Context()).Error("panic",
						"recover", rv, "stack", string(debug.Stack()))
					if !rec.wroteHeader {
						rec.WriteHeader(http.StatusInternalServerError)
					}
				}
				logger.FromContext(r.Context()).Info("request",
					"status", rec.status,
					"bytes", rec.bytes,
					"duration_ms", time.Since(start).Milliseconds(),
					"route", route(r))
			}()

			next.ServeHTTP(rec, r)
		})
	}
}

// requestID prefers the API Gateway v2 request id; falls back to a generated UUID.
func requestID(r *http.Request) string {
	if reqCtx, ok := core.GetAPIGatewayV2ContextFromContext(r.Context()); ok && reqCtx.RequestID != "" {
		return reqCtx.RequestID
	}
	return uuid.NewString()
}

// route returns the matched template (e.g. "GET /receivers/{receiverId}") once
// routing has run, falling back to method+path when no pattern matched.
func route(r *http.Request) string {
	if r.Pattern != "" {
		return r.Pattern
	}
	return r.Method + " " + r.URL.Path
}
