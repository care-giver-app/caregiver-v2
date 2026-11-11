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

func setTableEnv(t *testing.T) {
	t.Setenv("USERS_TABLE", "u")
	t.Setenv("CARE_GROUPS_TABLE", "c")
	t.Setenv("MEMBERSHIPS_TABLE", "m")
	t.Setenv("INVITATIONS_TABLE", "i")
	t.Setenv("RECEIVERS_TABLE", "r")
	t.Setenv("TRACKERS_TABLE", "tr")
	t.Setenv("EVENTS_TABLE", "ev")
	t.Setenv("SCHEDULED_ITEMS_TABLE", "si")
	t.Setenv("V1_USERS_TABLE", "v1u")
	t.Setenv("V1_TEAMS_TABLE", "v1t")
	t.Setenv("V1_MEMBERSHIPS_TABLE", "v1m")
	t.Setenv("V1_INVITATIONS_TABLE", "v1i")
	t.Setenv("V1_RECEIVERS_TABLE", "v1r")
	t.Setenv("V1_TRACKERS_TABLE", "v1tr")
	t.Setenv("V1_SCHEDULES_TABLE", "v1s")
	t.Setenv("V1_ENTRIES_TABLE", "v1e")
	t.Setenv("V1_JOURNAL_NOTES_TABLE", "v1jn")
	t.Setenv("AWS_REGION", "us-east-2")
	t.Setenv("AWS_ACCESS_KEY_ID", "x")
	t.Setenv("AWS_SECRET_ACCESS_KEY", "x")
	t.Setenv("DYNAMODB_ENDPOINT", "http://127.0.0.1:1") // never contacted by these tests
}

func TestNewMux_requiresV1TableEnv(t *testing.T) {
	setAppConfigEnv(t)
	setTableEnv(t)
	for _, k := range []string{
		"V1_USERS_TABLE", "V1_TEAMS_TABLE", "V1_MEMBERSHIPS_TABLE", "V1_INVITATIONS_TABLE",
		"V1_RECEIVERS_TABLE", "V1_TRACKERS_TABLE", "V1_SCHEDULES_TABLE", "V1_ENTRIES_TABLE",
		"V1_JOURNAL_NOTES_TABLE",
	} {
		t.Run(k, func(t *testing.T) {
			t.Setenv(k, "")
			if _, err := newMux(config.Config{Service: "api", Stage: "dev", Version: "0"}, testLogger()); err == nil {
				t.Fatalf("expected error when %s is empty", k)
			}
		})
	}
}

// Without API Gateway JWT claims the v1 authenticator answers 401 before any
// DynamoDB call, so a 401 (not 404/405) proves each route is registered.
func TestNewMux_v1RoutesAreRegisteredBehindAuth(t *testing.T) {
	setAppConfigEnv(t)
	setTableEnv(t)
	h, err := newMux(config.Config{Service: "api", Stage: "dev", Version: "0"}, testLogger())
	if err != nil {
		t.Fatalf("newMux: %v", err)
	}
	for _, rt := range []struct{ method, path string }{
		{http.MethodGet, "/v1/me"},
		{http.MethodPost, "/v1/teams"},
		{http.MethodGet, "/v1/me/invitations"},
		{http.MethodPost, "/v1/invitations/redeem"},
		{http.MethodGet, "/v1/teams/t1/receivers"},
		{http.MethodGet, "/v1/receivers/r1/trackers"},
		{http.MethodPost, "/v1/receivers/r1/trackers"},
		{http.MethodGet, "/v1/trackers/tr1"},
		{http.MethodPut, "/v1/trackers/tr1"},
		{http.MethodPost, "/v1/trackers/tr1/pause"},
		{http.MethodPost, "/v1/trackers/tr1/resume"},
		{http.MethodGet, "/v1/trackers/tr1/entries"},
		{http.MethodGet, "/v1/trackers/tr1/schedules"},
		{http.MethodGet, "/v1/tracker-templates"},
		{http.MethodGet, "/v1/receivers/r1/attention"},
		{http.MethodGet, "/v1/receivers/r1/coming-up"},
		{http.MethodGet, "/v1/receivers/r1/timeline"},
		{http.MethodGet, "/v1/receivers/r1/waiting"},
		{http.MethodGet, "/v1/entries/e1"},
		{http.MethodGet, "/v1/journal-notes/n1"},
		{http.MethodPost, "/v1/trackers/tr1/entries"},
		{http.MethodPost, "/v1/entries/e1/log"},
		{http.MethodPost, "/v1/entries/e1/skip"},
		{http.MethodPut, "/v1/entries/e1"},
		{http.MethodDelete, "/v1/entries/e1"},
		{http.MethodPost, "/v1/receivers/r1/journal-notes"},
		{http.MethodPut, "/v1/journal-notes/n1"},
		{http.MethodDelete, "/v1/journal-notes/n1"},
	} {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest(rt.method, rt.path, nil))
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("%s %s: code=%d", rt.method, rt.path, rec.Code)
		}
	}
}

func TestNewMux_healthServesWithoutContactingDynamo(t *testing.T) {
	setAppConfigEnv(t)
	setTableEnv(t)

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
