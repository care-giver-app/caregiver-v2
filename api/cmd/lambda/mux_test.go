package main

import (
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/config"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/logger"
)

func testLogger() *slog.Logger {
	return logger.NewWithWriter(io.Discard, "test", "test", slog.LevelInfo)
}

func setAppConfigEnv(t *testing.T) {
	t.Setenv("APPCONFIG_APPLICATION_ID", "a")
	t.Setenv("APPCONFIG_ENVIRONMENT_ID", "e")
	t.Setenv("APPCONFIG_PROFILE_ID", "p")
}

func TestNewMux_requiresTableEnv(t *testing.T) {
	setAppConfigEnv(t)
	if _, err := newMux(config.Config{Service: "api", Stage: "dev", Version: "0"}, testLogger()); err == nil {
		t.Fatal("expected error when table env is missing")
	}
}

func TestNewMux_healthServesWithoutContactingDynamo(t *testing.T) {
	setAppConfigEnv(t)
	t.Setenv("USERS_TABLE", "u")
	t.Setenv("CARE_GROUPS_TABLE", "c")
	t.Setenv("MEMBERSHIPS_TABLE", "m")
	t.Setenv("INVITATIONS_TABLE", "i")
	t.Setenv("RECEIVERS_TABLE", "r")
	t.Setenv("TRACKERS_TABLE", "tr")
	t.Setenv("EVENTS_TABLE", "ev")
	t.Setenv("SCHEDULED_ITEMS_TABLE", "si")
	t.Setenv("AWS_REGION", "us-east-2")
	t.Setenv("AWS_ACCESS_KEY_ID", "x")
	t.Setenv("AWS_SECRET_ACCESS_KEY", "x")
	t.Setenv("DYNAMODB_ENDPOINT", "http://127.0.0.1:1") // never contacted by /health

	h, err := newMux(config.Config{Service: "api", Stage: "dev", Version: "9.9"}, testLogger())
	if err != nil {
		t.Fatalf("newMux: %v", err)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/health", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("health code=%d", rec.Code)
	}
}
