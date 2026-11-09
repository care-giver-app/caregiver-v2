package store

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
)

// ScheduleStore reads and writes tracker schedules. A new schedule is written by
// Stores.AddSchedule, which keeps a tracker from holding a gap and a schedule
// at once.
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

func scheduleKey(scheduleID string) map[string]types.AttributeValue {
	return map[string]types.AttributeValue{"schedule_id": &types.AttributeValueMemberS{Value: scheduleID}}
}

// Get returns the schedule, removed or not. It returns ErrNotFound if there is
// no such schedule.
func (s *ScheduleStore) Get(ctx context.Context, scheduleID string) (domain.Schedule, error) {
	return getItem[domain.Schedule](ctx, s.client, s.table, scheduleKey(scheduleID))
}

// liveCond is the condition every write to a live schedule carries: it exists
// and has not been removed.
const liveCond = "attribute_exists(schedule_id) AND attribute_not_exists(removed_at)"

// Update writes A schedule's Save onto a live schedule: its label, rule, time,
// ends_on, planned_values, unrecorded_alert and updated_at, an empty label or
// ends_on removed. starts_on, removal and the generator's bookmark are untouched. It
// returns the schedule as stored, or ErrNotFound if it does not exist or has
// been removed.
func (s *ScheduleStore) Update(ctx context.Context, sc domain.Schedule) (domain.Schedule, error) {
	item, err := MarshalItem(sc)
	if err != nil {
		return domain.Schedule{}, err
	}
	set := "SET #rule = :rule, #time = :time, planned_values = :pv, unrecorded_alert = :ua, updated_at = :u"
	vals := map[string]types.AttributeValue{
		":rule": item["rule"], ":time": item["time"], ":pv": item["planned_values"], ":ua": item["unrecorded_alert"],
		":u": item["updated_at"],
	}
	var remove []string
	for _, a := range []string{"label", "ends_on"} {
		if v, ok := item[a]; ok {
			set += ", #" + a + " = :" + a
			vals[":"+a] = v
		} else {
			remove = append(remove, "#"+a)
		}
	}
	expr := set
	if len(remove) > 0 {
		expr += " REMOVE " + strings.Join(remove, ", ")
	}
	out, err := s.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName:                 aws.String(s.table),
		Key:                       scheduleKey(sc.ScheduleID),
		UpdateExpression:          aws.String(expr),
		ConditionExpression:       aws.String(liveCond),
		ExpressionAttributeNames:  map[string]string{"#rule": "rule", "#time": "time", "#label": "label", "#ends_on": "ends_on"},
		ExpressionAttributeValues: vals,
		ReturnValues:              types.ReturnValueAllNew,
	})
	var ccf *types.ConditionalCheckFailedException
	if errors.As(err, &ccf) {
		return domain.Schedule{}, ErrNotFound
	} else if err != nil {
		return domain.Schedule{}, err
	}
	var stored domain.Schedule
	if err := attributevalue.UnmarshalMap(out.Attributes, &stored); err != nil {
		return domain.Schedule{}, err
	}
	return stored, nil
}

// MarkRemoved sets removed_at on a live schedule. It returns ErrNotFound if
// the schedule does not exist or was already removed.
func (s *ScheduleStore) MarkRemoved(ctx context.Context, scheduleID string, at time.Time) error {
	_, err := s.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName:                 aws.String(s.table),
		Key:                       scheduleKey(scheduleID),
		UpdateExpression:          aws.String("SET removed_at = :at"),
		ConditionExpression:       aws.String(liveCond),
		ExpressionAttributeValues: map[string]types.AttributeValue{":at": timeKey(at)},
	})
	var ccf *types.ConditionalCheckFailedException
	if errors.As(err, &ccf) {
		return ErrNotFound
	}
	return err
}

// SetGeneratedThrough records the generator's bookmark on a live schedule that
// has not changed since the copy the generator worked from: its updated_at is
// still updatedAt (or, on a row written before updated_at existed, absent). It
// returns ErrNotFound if the schedule does not exist, has been removed, or has
// changed, so a generator racing a removal or a change learns of it.
func (s *ScheduleStore) SetGeneratedThrough(ctx context.Context, scheduleID, through string, updatedAt time.Time) error {
	_, err := s.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName:           aws.String(s.table),
		Key:                 scheduleKey(scheduleID),
		UpdateExpression:    aws.String("SET generated_through = :g"),
		ConditionExpression: aws.String(liveCond + " AND (updated_at = :u OR attribute_not_exists(updated_at))"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":g": &types.AttributeValueMemberS{Value: through},
			":u": timeKey(updatedAt),
		},
	})
	var ccf *types.ConditionalCheckFailedException
	if errors.As(err, &ccf) {
		return ErrNotFound
	}
	return err
}

// ListLive returns every schedule, on every team, that has not been removed,
// for the daily generator. It scans the table, which is fine at family scale.
func (s *ScheduleStore) ListLive(ctx context.Context) ([]domain.Schedule, error) {
	in := &dynamodb.ScanInput{
		TableName:        aws.String(s.table),
		FilterExpression: aws.String("attribute_not_exists(removed_at)"),
	}
	var all []domain.Schedule
	for {
		out, err := s.client.Scan(ctx, in)
		if err != nil {
			return nil, err
		}
		var page []domain.Schedule
		if err := attributevalue.UnmarshalListOfMaps(out.Items, &page); err != nil {
			return nil, err
		}
		all = append(all, page...)
		if len(out.LastEvaluatedKey) == 0 {
			return all, nil
		}
		in.ExclusiveStartKey = out.LastEvaluatedKey
	}
}
