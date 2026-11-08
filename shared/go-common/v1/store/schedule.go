package store

import (
	"context"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
)

// ScheduleStore reads tracker schedules. Writing them belongs to the schedule
// endpoints and the generator.
type ScheduleStore struct {
	client *dynamodb.Client
	table  string
}

func (s *ScheduleStore) liveQuery(trackerID string) *dynamodb.QueryInput {
	return &dynamodb.QueryInput{
		TableName:              aws.String(s.table),
		IndexName:              aws.String(trackerIndex),
		KeyConditionExpression: aws.String("tracker_id = :t"),
		FilterExpression:       aws.String("attribute_not_exists(removed_at)"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":t": &types.AttributeValueMemberS{Value: trackerID},
		},
	}
}

// ListLiveByTracker returns the tracker's schedules that have not been
// removed, oldest first.
func (s *ScheduleStore) ListLiveByTracker(ctx context.Context, trackerID string) ([]domain.Schedule, error) {
	return queryAll[domain.Schedule](ctx, s.client, s.liveQuery(trackerID))
}

// CountLiveByTracker counts the tracker's schedules that have not been removed.
func (s *ScheduleStore) CountLiveByTracker(ctx context.Context, trackerID string) (int, error) {
	in := s.liveQuery(trackerID)
	in.Select = types.SelectCount
	n := 0
	for {
		out, err := s.client.Query(ctx, in)
		if err != nil {
			return 0, err
		}
		n += int(out.Count)
		if len(out.LastEvaluatedKey) == 0 {
			return n, nil
		}
		in.ExclusiveStartKey = out.LastEvaluatedKey
	}
}

// BatchGet returns the schedules for the given ids, removed ones included, keyed
// by schedule_id, so a past entry can still name the schedule it came from.
// Missing ids are simply absent from the result.
func (s *ScheduleStore) BatchGet(ctx context.Context, ids []string) (map[string]domain.Schedule, error) {
	return batchGetItems(ctx, s.client, s.table, "schedule_id", ids, func(sc domain.Schedule) string { return sc.ScheduleID })
}
