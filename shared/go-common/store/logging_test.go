package store_test

import (
	"bytes"
	"context"
	"log/slog"
	"strings"
	"testing"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/logger"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store/dynamotest"
)

func TestDynamoOpsLoggedAtDebug(t *testing.T) {
	stores := dynamotest.Start(t)

	var buf bytes.Buffer
	log := logger.NewWithWriter(&buf, "s", "test", slog.LevelDebug)
	ctx := logger.NewContext(context.Background(), log)

	// A lookup for a missing user still issues a GetItem against DynamoDB.
	_, _ = stores.Users.Get(ctx, "no-such-user")

	out := buf.String()
	if !strings.Contains(out, "\"msg\":\"dynamodb op\"") {
		t.Fatalf("no dynamodb op line: %s", out)
	}
	if !strings.Contains(out, "\"operation\":\"GetItem\"") {
		t.Fatalf("operation name missing: %s", out)
	}
}

func TestDynamoOpsSilentAtInfo(t *testing.T) {
	stores := dynamotest.Start(t)

	var buf bytes.Buffer
	log := logger.NewWithWriter(&buf, "s", "test", slog.LevelInfo)
	ctx := logger.NewContext(context.Background(), log)

	_, _ = stores.Users.Get(ctx, "no-such-user")

	if strings.Contains(buf.String(), "dynamodb op") {
		t.Fatalf("op line emitted at info level: %s", buf.String())
	}
}
