package main

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"

	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	cip "github.com/aws/aws-sdk-go-v2/service/cognitoidentityprovider"
	"github.com/aws/aws-sdk-go-v2/service/sns"

	"github.com/care-giver-app/caregiver-v2/api/internal/handlers"
	"github.com/care-giver-app/caregiver-v2/api/internal/middleware"
	v1 "github.com/care-giver-app/caregiver-v2/api/internal/v1"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/config"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/flags"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store"
	v1store "github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
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
	si := handlers.NewScheduledItems(stores)
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

	mux.Handle("GET /trackers/{trackerId}/scheduled-items", authn.Wrap(http.HandlerFunc(si.List)))
	mux.Handle("POST /trackers/{trackerId}/scheduled-items", authn.Wrap(http.HandlerFunc(si.Create)))
	mux.Handle("GET /receivers/{receiverId}/scheduled-items", authn.Wrap(http.HandlerFunc(si.ListByReceiver)))
	mux.Handle("GET /scheduled-items/{scheduledItemId}", authn.Wrap(http.HandlerFunc(si.Get)))
	mux.Handle("PUT /scheduled-items/{scheduledItemId}", authn.Wrap(http.HandlerFunc(si.Update)))
	mux.Handle("DELETE /scheduled-items/{scheduledItemId}", authn.Wrap(http.HandlerFunc(si.Delete)))

	mux.Handle("GET /tracker-templates", authn.Wrap(http.HandlerFunc(tpl.List)))

	// /v1 — the target model, served beside the routes above until cutover.
	v1Stores, err := newV1Stores(context.Background())
	if err != nil {
		return nil, err
	}
	v1authn := v1.NewAuthenticator(v1Stores)
	v1teams := v1.NewTeams(v1Stores)
	v1inv := v1.NewInvitations(v1Stores)
	mux.Handle("GET /v1/me", v1authn.Wrap(v1.NewMe(v1Stores)))
	mux.Handle("POST /v1/teams", v1authn.Wrap(http.HandlerFunc(v1teams.Create)))
	mux.Handle("GET /v1/me/invitations", v1authn.Wrap(http.HandlerFunc(v1inv.Mine)))
	mux.Handle("POST /v1/invitations/redeem", v1authn.Wrap(http.HandlerFunc(v1inv.Redeem)))

	v1rcv := v1.NewReceivers(v1Stores)
	v1trk := v1.NewTrackers(v1Stores)
	mux.Handle("GET /v1/teams/{teamId}/receivers", v1authn.Wrap(http.HandlerFunc(v1rcv.ListByTeam)))
	mux.Handle("POST /v1/teams/{teamId}/receivers", v1authn.Wrap(http.HandlerFunc(v1rcv.Create)))
	mux.Handle("GET /v1/receivers/{receiverId}/trackers", v1authn.Wrap(http.HandlerFunc(v1trk.ListByReceiver)))
	mux.Handle("POST /v1/receivers/{receiverId}/trackers", v1authn.Wrap(http.HandlerFunc(v1trk.Create)))
	mux.Handle("GET /v1/trackers/{trackerId}", v1authn.Wrap(http.HandlerFunc(v1trk.Get)))
	mux.Handle("PUT /v1/trackers/{trackerId}", v1authn.Wrap(http.HandlerFunc(v1trk.Edit)))
	mux.Handle("POST /v1/trackers/{trackerId}/pause", v1authn.Wrap(http.HandlerFunc(v1trk.Pause)))
	mux.Handle("POST /v1/trackers/{trackerId}/resume", v1authn.Wrap(http.HandlerFunc(v1trk.Resume)))
	mux.Handle("GET /v1/trackers/{trackerId}/entries", v1authn.Wrap(http.HandlerFunc(v1trk.Entries)))
	mux.Handle("GET /v1/trackers/{trackerId}/schedules", v1authn.Wrap(http.HandlerFunc(v1trk.Schedules)))
	mux.Handle("POST /v1/trackers/{trackerId}/schedules", v1authn.Wrap(http.HandlerFunc(v1trk.AddSchedule)))
	mux.Handle("PUT /v1/schedules/{scheduleId}", v1authn.Wrap(http.HandlerFunc(v1trk.ChangeSchedule)))
	mux.Handle("DELETE /v1/schedules/{scheduleId}", v1authn.Wrap(http.HandlerFunc(v1trk.RemoveSchedule)))
	mux.Handle("GET /v1/tracker-templates", v1authn.Wrap(http.HandlerFunc(v1.NewTemplates().List)))

	v1home := v1.NewHome(v1Stores)
	mux.Handle("GET /v1/receivers/{receiverId}/attention", v1authn.Wrap(http.HandlerFunc(v1home.Attention)))
	mux.Handle("GET /v1/receivers/{receiverId}/coming-up", v1authn.Wrap(http.HandlerFunc(v1home.ComingUp)))
	mux.Handle("GET /v1/receivers/{receiverId}/timeline", v1authn.Wrap(http.HandlerFunc(v1home.Timeline)))
	mux.Handle("GET /v1/receivers/{receiverId}/waiting", v1authn.Wrap(http.HandlerFunc(v1home.Waiting)))
	mux.Handle("GET /v1/entries/{entryId}", v1authn.Wrap(http.HandlerFunc(v1home.Entry)))
	mux.Handle("GET /v1/journal-notes/{noteId}", v1authn.Wrap(http.HandlerFunc(v1home.JournalNote)))
	mux.Handle("POST /v1/trackers/{trackerId}/entries", v1authn.Wrap(http.HandlerFunc(v1home.AddEntry)))
	mux.Handle("POST /v1/entries/{entryId}/log", v1authn.Wrap(http.HandlerFunc(v1home.LogEntry)))
	mux.Handle("POST /v1/entries/{entryId}/skip", v1authn.Wrap(http.HandlerFunc(v1home.SkipEntry)))
	mux.Handle("PUT /v1/entries/{entryId}", v1authn.Wrap(http.HandlerFunc(v1home.ChangeEntry)))
	mux.Handle("DELETE /v1/entries/{entryId}", v1authn.Wrap(http.HandlerFunc(v1home.DeleteEntry)))
	mux.Handle("POST /v1/receivers/{receiverId}/journal-notes", v1authn.Wrap(http.HandlerFunc(v1home.AddJournalNote)))
	mux.Handle("PUT /v1/journal-notes/{noteId}", v1authn.Wrap(http.HandlerFunc(v1home.ChangeJournalNote)))
	mux.Handle("DELETE /v1/journal-notes/{noteId}", v1authn.Wrap(http.HandlerFunc(v1home.DeleteJournalNote)))

	mux.Handle("GET /v1/teams/{teamId}", v1authn.Wrap(http.HandlerFunc(v1teams.Get)))
	mux.Handle("POST /v1/teams/{teamId}/close", v1authn.Wrap(http.HandlerFunc(v1teams.Close)))
	mux.Handle("GET /v1/teams/{teamId}/invitations", v1authn.Wrap(http.HandlerFunc(v1inv.ListByTeam)))
	mux.Handle("POST /v1/teams/{teamId}/invitations", v1authn.Wrap(http.HandlerFunc(v1inv.Create)))
	mux.Handle("PUT /v1/teams/{teamId}/members/{userId}", v1authn.Wrap(http.HandlerFunc(v1teams.ChangeRole)))
	mux.Handle("DELETE /v1/teams/{teamId}/members/{userId}", v1authn.Wrap(http.HandlerFunc(v1teams.RemoveMember)))
	mux.Handle("GET /v1/teams/{teamId}/my-notifications", v1authn.Wrap(http.HandlerFunc(v1teams.MyNotifications)))
	mux.Handle("PUT /v1/teams/{teamId}/my-notifications", v1authn.Wrap(http.HandlerFunc(v1teams.ChangeMyNotifications)))
	mux.Handle("GET /v1/receivers/{receiverId}", v1authn.Wrap(http.HandlerFunc(v1rcv.Get)))
	mux.Handle("PUT /v1/receivers/{receiverId}", v1authn.Wrap(http.HandlerFunc(v1rcv.Change)))
	mux.Handle("POST /v1/receivers/{receiverId}/archive", v1authn.Wrap(http.HandlerFunc(v1rcv.Archive)))
	mux.Handle("POST /v1/receivers/{receiverId}/restore", v1authn.Wrap(http.HandlerFunc(v1rcv.Restore)))
	mux.Handle("PUT /v1/receivers/{receiverId}/care-instructions", v1authn.Wrap(http.HandlerFunc(v1rcv.ChangeCareInstructions)))
	mux.Handle("PUT /v1/receivers/{receiverId}/emergency-contacts", v1authn.Wrap(http.HandlerFunc(v1rcv.ChangeEmergencyContacts)))
	v1cov := v1.NewCoverage(v1Stores)
	mux.Handle("GET /v1/receivers/{receiverId}/on-duty", v1authn.Wrap(http.HandlerFunc(v1cov.OnDuty)))
	mux.Handle("GET /v1/receivers/{receiverId}/assignments", v1authn.Wrap(http.HandlerFunc(v1cov.Assignments)))
	mux.Handle("POST /v1/receivers/{receiverId}/assignments", v1authn.Wrap(http.HandlerFunc(v1cov.AddAssignment)))
	mux.Handle("PUT /v1/assignments/{assignmentId}", v1authn.Wrap(http.HandlerFunc(v1cov.ChangeAssignment)))
	mux.Handle("DELETE /v1/assignments/{assignmentId}", v1authn.Wrap(http.HandlerFunc(v1cov.RemoveAssignment)))
	mux.Handle("GET /v1/receivers/{receiverId}/coverage-schedules", v1authn.Wrap(http.HandlerFunc(v1cov.CoverageSchedules)))
	mux.Handle("POST /v1/receivers/{receiverId}/coverage-schedules", v1authn.Wrap(http.HandlerFunc(v1cov.AddCoverageSchedule)))
	mux.Handle("PUT /v1/coverage-schedules/{coverageScheduleId}", v1authn.Wrap(http.HandlerFunc(v1cov.ChangeCoverageSchedule)))
	mux.Handle("DELETE /v1/coverage-schedules/{coverageScheduleId}", v1authn.Wrap(http.HandlerFunc(v1cov.RemoveCoverageSchedule)))

	settings, err := newSettings(context.Background())
	if err != nil {
		return nil, err
	}
	v1acct := v1.NewAccount(v1Stores, settings.identity)
	mux.Handle("PATCH /v1/me", v1authn.Wrap(http.HandlerFunc(v1acct.Change)))
	mux.Handle("POST /v1/me/email", v1authn.Wrap(http.HandlerFunc(v1acct.StartEmailChange)))
	// Served to a closed account too, so a close stopped partway can finish.
	mux.Handle("POST /v1/me/close", v1authn.WrapClosing(http.HandlerFunc(v1acct.Close)))
	// No API Gateway authorizer here: the token is optional, so it is verified
	// in-process when there is one, and a request without one is anonymous.
	v1bearer := v1.NewBearerAuthenticator(v1Stores, settings.verifier)
	mux.Handle("POST /v1/feedback", v1bearer.WrapOptional(v1.NewFeedback(settings.feedback)))

	return middleware.RequestLogger(log)(mux), nil
}

// settings is what the Settings routes need beyond the tables: the identity
// provider, a verifier for the one route without the gateway's authorizer,
// and where feedback goes.
type settings struct {
	identity v1.IdentityProvider
	verifier *v1.TokenVerifier
	feedback v1.FeedbackSender
}

func newSettings(ctx context.Context) (settings, error) {
	poolID, clientID := os.Getenv("COGNITO_USER_POOL_ID"), os.Getenv("COGNITO_APP_CLIENT_ID")
	topic := os.Getenv("V1_FEEDBACK_TOPIC_ARN")
	region := os.Getenv("AWS_REGION")
	if poolID == "" || clientID == "" || topic == "" || region == "" {
		return settings{}, fmt.Errorf("COGNITO_USER_POOL_ID, COGNITO_APP_CLIENT_ID, V1_FEEDBACK_TOPIC_ARN and AWS_REGION must all be set")
	}
	cfg, err := awsconfig.LoadDefaultConfig(ctx, awsconfig.WithRegion(region))
	if err != nil {
		return settings{}, err
	}
	return settings{
		identity: v1.NewCognitoIdentity(cip.NewFromConfig(cfg), poolID, clientID),
		verifier: v1.NewCognitoVerifier(region, poolID, clientID),
		feedback: v1.NewSNSFeedbackSender(sns.NewFromConfig(cfg), topic),
	}, nil
}

func newStores(ctx context.Context) (*store.Stores, error) {
	names := store.TableNames{
		Users:          os.Getenv("USERS_TABLE"),
		CareGroups:     os.Getenv("CARE_GROUPS_TABLE"),
		Memberships:    os.Getenv("MEMBERSHIPS_TABLE"),
		Invitations:    os.Getenv("INVITATIONS_TABLE"),
		Receivers:      os.Getenv("RECEIVERS_TABLE"),
		Trackers:       os.Getenv("TRACKERS_TABLE"),
		Events:         os.Getenv("EVENTS_TABLE"),
		ScheduledItems: os.Getenv("SCHEDULED_ITEMS_TABLE"),
	}
	if names.Users == "" || names.CareGroups == "" || names.Memberships == "" || names.Invitations == "" ||
		names.Receivers == "" || names.Trackers == "" || names.Events == "" || names.ScheduledItems == "" {
		return nil, fmt.Errorf("all DynamoDB table env vars must be set")
	}
	// DYNAMODB_ENDPOINT is empty in Lambda (default AWS resolution); set for local/dev.
	client, err := store.NewClient(ctx, os.Getenv("DYNAMODB_ENDPOINT"))
	if err != nil {
		return nil, err
	}
	return store.New(client, names), nil
}

func newV1Stores(ctx context.Context) (*v1store.Stores, error) {
	names := v1store.TableNames{
		Users:             os.Getenv("V1_USERS_TABLE"),
		Teams:             os.Getenv("V1_TEAMS_TABLE"),
		Memberships:       os.Getenv("V1_MEMBERSHIPS_TABLE"),
		Invitations:       os.Getenv("V1_INVITATIONS_TABLE"),
		Receivers:         os.Getenv("V1_RECEIVERS_TABLE"),
		CareInstructions:  os.Getenv("V1_CARE_INSTRUCTIONS_TABLE"),
		Trackers:          os.Getenv("V1_TRACKERS_TABLE"),
		Schedules:         os.Getenv("V1_SCHEDULES_TABLE"),
		Entries:           os.Getenv("V1_ENTRIES_TABLE"),
		JournalNotes:      os.Getenv("V1_JOURNAL_NOTES_TABLE"),
		CoverageSchedules: os.Getenv("V1_COVERAGE_SCHEDULES_TABLE"),
		Assignments:       os.Getenv("V1_ASSIGNMENTS_TABLE"),
	}
	if names.Users == "" || names.Teams == "" || names.Memberships == "" || names.Invitations == "" ||
		names.Receivers == "" || names.Trackers == "" || names.Schedules == "" || names.Entries == "" ||
		names.JournalNotes == "" || names.CareInstructions == "" || names.CoverageSchedules == "" || names.Assignments == "" {
		return nil, fmt.Errorf("all V1_*_TABLE env vars (users, teams, memberships, invitations, receivers, care instructions, trackers, schedules, entries, journal notes, coverage schedules, assignments) must be set")
	}
	client, err := v1store.NewClient(ctx, os.Getenv("DYNAMODB_ENDPOINT"))
	if err != nil {
		return nil, err
	}
	return v1store.New(client, names), nil
}
