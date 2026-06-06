package main

import (
	"net/http"

	"github.com/care-giver-app/caregiver-v2/api/internal/handlers"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/config"
)

func newMux(cfg config.Config) http.Handler {
	mux := http.NewServeMux()
	mux.Handle("GET /health", handlers.NewHealth(cfg.Version, nil))
	return mux
}
