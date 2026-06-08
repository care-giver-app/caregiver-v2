package main

import (
	"fmt"
	"net/http"
	"os"

	"github.com/care-giver-app/caregiver-v2/api/internal/handlers"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/config"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/flags"
)

func newMux(cfg config.Config) (http.Handler, error) {
	mux := http.NewServeMux()
	mux.Handle("GET /health", handlers.NewHealth(cfg.Version, nil))

	appID := os.Getenv("APPCONFIG_APPLICATION_ID")
	envID := os.Getenv("APPCONFIG_ENVIRONMENT_ID")
	profileID := os.Getenv("APPCONFIG_PROFILE_ID")
	if appID == "" || envID == "" || profileID == "" {
		return nil, fmt.Errorf(
			"APPCONFIG_APPLICATION_ID/ENVIRONMENT_ID/PROFILE_ID must all be set",
		)
	}
	flagClient := flags.NewClientFromEnv(appID, envID, profileID)
	mux.Handle("GET /flags", handlers.NewFlags(flagClient, nil))
	return mux, nil
}
