package store

import (
	"context"
	"time"

	awsmiddleware "github.com/aws/aws-sdk-go-v2/aws/middleware"
	"github.com/aws/smithy-go/middleware"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/logger"
)

// logOps registers a Finalize middleware that logs every DynamoDB API call at
// Debug with operation name, duration, and outcome. The logger is pulled from
// the operation's context so each line inherits request_id/user_id.
func logOps(stack *middleware.Stack) error {
	return stack.Finalize.Add(
		middleware.FinalizeMiddlewareFunc(
			"CaregiverDynamoLog",
			func(ctx context.Context, in middleware.FinalizeInput, next middleware.FinalizeHandler) (
				middleware.FinalizeOutput, middleware.Metadata, error,
			) {
				start := time.Now()
				out, md, err := next.HandleFinalize(ctx, in)
				log := logger.FromContext(ctx)
				dur := time.Since(start).Milliseconds()
				op := awsmiddleware.GetOperationName(ctx)
				if err != nil {
					log.Debug("dynamodb op", "operation", op, "duration_ms", dur, "ok", false, "err", err.Error())
				} else {
					log.Debug("dynamodb op", "operation", op, "duration_ms", dur, "ok", true)
				}
				return out, md, err
			},
		),
		middleware.After,
	)
}
