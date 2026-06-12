package main

import (
	"context"
	"fmt"
	"net/http"
	"os"

	"github.com/care-giver-app/caregiver-v2/api/internal/handlers"
	"github.com/care-giver-app/caregiver-v2/api/internal/middleware"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/config"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/flags"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store"
)

func newMux(cfg config.Config) (http.Handler, error) {
	mux := http.NewServeMux()
	mux.Handle("GET /health", handlers.NewHealth(cfg.Version, nil))

	appID := os.Getenv("APPCONFIG_APPLICATION_ID")
	envID := os.Getenv("APPCONFIG_ENVIRONMENT_ID")
	profileID := os.Getenv("APPCONFIG_PROFILE_ID")
	if appID == "" || envID == "" || profileID == "" {
		return nil, fmt.Errorf("APPCONFIG_APPLICATION_ID/ENVIRONMENT_ID/PROFILE_ID must all be set")
	}
	flagClient := flags.NewClientFromEnv(appID, envID, profileID)
	mux.Handle("GET /flags", handlers.NewFlags(flagClient, nil))

	stores, err := newStores(context.Background())
	if err != nil {
		return nil, err
	}
	authn := middleware.NewAuthenticator(stores)
	cg := handlers.NewCareGroups(stores)
	inv := handlers.NewInvitations(stores)

	mux.Handle("GET /me", authn.Wrap(handlers.NewMe(stores)))
	mux.Handle("POST /care-groups", authn.Wrap(http.HandlerFunc(cg.Create)))
	mux.Handle("POST /care-groups/{careGroupId}/invitations", authn.Wrap(http.HandlerFunc(cg.CreateInvitation)))
	mux.Handle("DELETE /care-groups/{careGroupId}/invitations/{token}", authn.Wrap(http.HandlerFunc(cg.RevokeInvitation)))
	mux.Handle("GET /invitations/mine", authn.Wrap(http.HandlerFunc(inv.Mine)))
	mux.Handle("POST /invitations/{token}/accept", authn.Wrap(http.HandlerFunc(inv.Accept)))

	return mux, nil
}

func newStores(ctx context.Context) (*store.Stores, error) {
	names := store.TableNames{
		Users:       os.Getenv("USERS_TABLE"),
		CareGroups:  os.Getenv("CARE_GROUPS_TABLE"),
		Memberships: os.Getenv("MEMBERSHIPS_TABLE"),
		Invitations: os.Getenv("INVITATIONS_TABLE"),
	}
	if names.Users == "" || names.CareGroups == "" || names.Memberships == "" || names.Invitations == "" {
		return nil, fmt.Errorf("USERS_TABLE/CARE_GROUPS_TABLE/MEMBERSHIPS_TABLE/INVITATIONS_TABLE must all be set")
	}
	// DYNAMODB_ENDPOINT is empty in Lambda (default AWS resolution); set for local/dev.
	client, err := store.NewClient(ctx, os.Getenv("DYNAMODB_ENDPOINT"))
	if err != nil {
		return nil, err
	}
	return store.New(client, names), nil
}
