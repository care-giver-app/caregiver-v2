package main

import (
	"context"
	"log/slog"
	"os"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/awslabs/aws-lambda-go-api-proxy/httpadapter"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/config"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/logger"
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

	mux, err := newMux(cfg)
	if err != nil {
		log.Error("mux init failed", "err", err)
		os.Exit(1)
	}
	adapter := httpadapter.NewV2(mux)

	lambda.Start(func(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
		return adapter.ProxyWithContext(ctx, req)
	})
}
