// Command generator is the daily occurrence generator (docs/adr/0012-*, "The
// generator"). EventBridge invokes it once a day; for every live schedule it
// tops up the scheduled entries through generate.Horizon. It can also be
// invoked by hand (aws lambda invoke) and returns the run's Summary.
package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"time"
	// Embedded zone data: occurrences are resolved in each receiver's IANA zone,
	// and the Lambda runtime image is not guaranteed to ship /usr/share/zoneinfo.
	_ "time/tzdata"

	"github.com/aws/aws-lambda-go/lambda"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/config"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/logger"
	v1store "github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
)

func main() {
	cfg, err := config.FromEnv()
	if err != nil {
		// Fall back to plain stderr because logger requires config.
		slog.New(slog.NewJSONHandler(os.Stderr, nil)).Error("config error", "err", err)
		os.Exit(1)
	}
	log := logger.New(cfg.Service, cfg.Stage)
	log.Info("starting", "version", cfg.Version)

	stores, err := newStores(context.Background())
	if err != nil {
		log.Error("stores init failed", "err", err)
		os.Exit(1)
	}
	lambda.Start(func(ctx context.Context) (Summary, error) {
		return Run(ctx, stores, log, time.Now().UTC())
	})
}

// newStores builds the v1 stores from the same V1_*_TABLE variables the API
// reads. The generator touches only schedules, trackers, receivers and entries.
func newStores(ctx context.Context) (*v1store.Stores, error) {
	names := v1store.TableNames{
		Receivers: os.Getenv("V1_RECEIVERS_TABLE"),
		Trackers:  os.Getenv("V1_TRACKERS_TABLE"),
		Schedules: os.Getenv("V1_SCHEDULES_TABLE"),
		Entries:   os.Getenv("V1_ENTRIES_TABLE"),
	}
	if names.Receivers == "" || names.Trackers == "" || names.Schedules == "" || names.Entries == "" {
		return nil, fmt.Errorf("V1_RECEIVERS_TABLE, V1_TRACKERS_TABLE, V1_SCHEDULES_TABLE and V1_ENTRIES_TABLE must be set")
	}
	// DYNAMODB_ENDPOINT is empty in Lambda (default AWS resolution); set for local/dev.
	client, err := v1store.NewClient(ctx, os.Getenv("DYNAMODB_ENDPOINT"))
	if err != nil {
		return nil, err
	}
	return v1store.New(client, names), nil
}
