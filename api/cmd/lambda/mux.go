package main

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"

	"github.com/care-giver-app/caregiver-v2/api/internal/handlers"
	"github.com/care-giver-app/caregiver-v2/api/internal/middleware"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/config"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/flags"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store"
)

func newMux(cfg config.Config, log *slog.Logger) (http.Handler, error) {
	mux := http.NewServeMux()
	mux.Handle("GET /health", handlers.NewHealth(cfg.Version, nil))

	appID := os.Getenv("APPCONFIG_APPLICATION_ID")
	envID := os.Getenv("APPCONFIG_ENVIRONMENT_ID")
	profileID := os.Getenv("APPCONFIG_PROFILE_ID")
	if appID == "" || envID == "" || profileID == "" {
		return nil, fmt.Errorf("APPCONFIG_APPLICATION_ID/ENVIRONMENT_ID/PROFILE_ID must all be set")
	}
	flagClient := flags.NewClientFromEnv(appID, envID, profileID)
	mux.Handle("GET /flags", handlers.NewFlags(flagClient))

	stores, err := newStores(context.Background())
	if err != nil {
		return nil, err
	}
	authn := middleware.NewAuthenticator(stores)
	cg := handlers.NewCareGroups(stores)
	mbr := handlers.NewMembers(stores)
	inv := handlers.NewInvitations(stores)
	rcv := handlers.NewReceivers(stores)
	trk := handlers.NewTrackers(stores)
	evt := handlers.NewEvents(stores)
	tpl := handlers.NewTemplates()

	mux.Handle("GET /me", authn.Wrap(handlers.NewMe(stores)))
	mux.Handle("POST /care-groups", authn.Wrap(http.HandlerFunc(cg.Create)))
	mux.Handle("GET /care-groups/{careGroupId}/members", authn.Wrap(mbr))
	mux.Handle("POST /care-groups/{careGroupId}/invitations", authn.Wrap(http.HandlerFunc(cg.CreateInvitation)))
	mux.Handle("DELETE /care-groups/{careGroupId}/invitations/{token}", authn.Wrap(http.HandlerFunc(cg.RevokeInvitation)))
	mux.Handle("GET /invitations/mine", authn.Wrap(http.HandlerFunc(inv.Mine)))
	mux.Handle("POST /invitations/{token}/accept", authn.Wrap(http.HandlerFunc(inv.Accept)))

	mux.Handle("GET /receivers", authn.Wrap(http.HandlerFunc(rcv.List)))
	mux.Handle("POST /care-groups/{careGroupId}/receivers", authn.Wrap(http.HandlerFunc(rcv.Create)))
	mux.Handle("GET /receivers/{receiverId}", authn.Wrap(http.HandlerFunc(rcv.Get)))
	mux.Handle("PATCH /receivers/{receiverId}", authn.Wrap(http.HandlerFunc(rcv.Update)))
	mux.Handle("DELETE /receivers/{receiverId}", authn.Wrap(http.HandlerFunc(rcv.Archive)))

	mux.Handle("GET /receivers/{receiverId}/trackers", authn.Wrap(http.HandlerFunc(trk.ListByReceiver)))
	mux.Handle("POST /receivers/{receiverId}/trackers", authn.Wrap(http.HandlerFunc(trk.Create)))
	mux.Handle("GET /trackers/{trackerId}", authn.Wrap(http.HandlerFunc(trk.Get)))
	mux.Handle("PATCH /trackers/{trackerId}", authn.Wrap(http.HandlerFunc(trk.Update)))
	mux.Handle("DELETE /trackers/{trackerId}", authn.Wrap(http.HandlerFunc(trk.Archive)))

	mux.Handle("GET /trackers/{trackerId}/events", authn.Wrap(http.HandlerFunc(evt.List)))
	mux.Handle("POST /trackers/{trackerId}/events", authn.Wrap(http.HandlerFunc(evt.Create)))
	mux.Handle("GET /trackers/{trackerId}/events/{eventId}", authn.Wrap(http.HandlerFunc(evt.Get)))
	mux.Handle("PATCH /trackers/{trackerId}/events/{eventId}", authn.Wrap(http.HandlerFunc(evt.Update)))
	mux.Handle("DELETE /trackers/{trackerId}/events/{eventId}", authn.Wrap(http.HandlerFunc(evt.Delete)))

	mux.Handle("GET /tracker-templates", authn.Wrap(http.HandlerFunc(tpl.List)))

	return middleware.RequestLogger(log)(mux), nil
}

func newStores(ctx context.Context) (*store.Stores, error) {
	names := store.TableNames{
		Users:       os.Getenv("USERS_TABLE"),
		CareGroups:  os.Getenv("CARE_GROUPS_TABLE"),
		Memberships: os.Getenv("MEMBERSHIPS_TABLE"),
		Invitations: os.Getenv("INVITATIONS_TABLE"),
		Receivers:   os.Getenv("RECEIVERS_TABLE"),
		Trackers:    os.Getenv("TRACKERS_TABLE"),
		Events:      os.Getenv("EVENTS_TABLE"),
	}
	if names.Users == "" || names.CareGroups == "" || names.Memberships == "" || names.Invitations == "" ||
		names.Receivers == "" || names.Trackers == "" || names.Events == "" {
		return nil, fmt.Errorf("all DynamoDB table env vars must be set")
	}
	// DYNAMODB_ENDPOINT is empty in Lambda (default AWS resolution); set for local/dev.
	client, err := store.NewClient(ctx, os.Getenv("DYNAMODB_ENDPOINT"))
	if err != nil {
		return nil, err
	}
	return store.New(client, names), nil
}
