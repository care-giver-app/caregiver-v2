package store

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
)

type TrackerStore struct {
	client *dynamodb.Client
	table  string
}

func trackerKey(trackerID string) map[string]types.AttributeValue {
	return map[string]types.AttributeValue{"tracker_id": &types.AttributeValueMemberS{Value: trackerID}}
}

func (s *TrackerStore) Get(ctx context.Context, trackerID string) (domain.Tracker, error) {
	return getItem[domain.Tracker](ctx, s.client, s.table, trackerKey(trackerID))
}

// ListByReceiver returns every tracker of the receiver, active and paused,
// oldest first. Sorting for display is the caller's.
func (s *TrackerStore) ListByReceiver(ctx context.Context, receiverID string) ([]domain.Tracker, error) {
	return queryAll[domain.Tracker](ctx, s.client, &dynamodb.QueryInput{
		TableName:              aws.String(s.table),
		IndexName:              aws.String(receiverIndex),
		KeyConditionExpression: aws.String("receiver_id = :r"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":r": &types.AttributeValueMemberS{Value: receiverID},
		},
	})
}

// Create writes a new tracker. The put is conditional so an id collision fails
// with a ConditionalCheckFailedException instead of overwriting.
func (s *TrackerStore) Create(ctx context.Context, t domain.Tracker) error {
	return s.put(ctx, t, "attribute_not_exists(tracker_id)")
}

// editedAttrs are what Edit tracker's Save changes. Status and its by/at stay
// with SetStatus, so a pause landing mid-edit is never undone.
var editedAttrs = []string{"name", "icon", "color", "fields", "gap_hours"}

// Put writes Edit tracker's Save onto an existing tracker: only editedAttrs, an
// absent one removed. It returns ErrNotFound if the tracker no longer exists.
func (s *TrackerStore) Put(ctx context.Context, t domain.Tracker) error {
	item, err := MarshalItem(t)
	if err != nil {
		return err
	}
	names := map[string]string{}
	values := map[string]types.AttributeValue{}
	var set, remove []string
	for i, a := range editedAttrs {
		n := fmt.Sprintf("#a%d", i)
		names[n] = a
		if v, ok := item[a]; ok {
			values[fmt.Sprintf(":a%d", i)] = v
			set = append(set, fmt.Sprintf("%s = :a%d", n, i))
		} else {
			remove = append(remove, n)
		}
	}
	expr := "SET " + strings.Join(set, ", ")
	if len(remove) > 0 {
		expr += " REMOVE " + strings.Join(remove, ", ")
	}
	_, err = s.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName:                 aws.String(s.table),
		Key:                       map[string]types.AttributeValue{"tracker_id": &types.AttributeValueMemberS{Value: t.TrackerID}},
		UpdateExpression:          aws.String(expr),
		ConditionExpression:       aws.String("attribute_exists(tracker_id)"),
		ExpressionAttributeNames:  names,
		ExpressionAttributeValues: values,
	})
	var ccf *types.ConditionalCheckFailedException
	if errors.As(err, &ccf) {
		return ErrNotFound
	}
	return err
}

func (s *TrackerStore) put(ctx context.Context, t domain.Tracker, cond string) error {
	item, err := MarshalItem(t)
	if err != nil {
		return err
	}
	_, err = s.client.PutItem(ctx, &dynamodb.PutItemInput{
		TableName:           aws.String(s.table),
		Item:                item,
		ConditionExpression: aws.String(cond),
	})
	return err
}

// SetStatus pauses or resumes a tracker and returns it as stored. Pausing sets
// paused_by/paused_at; resuming removes them and sets resumed_at. A tracker already in the status
// is returned unchanged, so a repeat keeps the original paused_at. It returns
// ErrNotFound if the tracker does not exist.
func (s *TrackerStore) SetStatus(ctx context.Context, trackerID string, status domain.TrackerStatus, by string, at time.Time) (domain.Tracker, error) {
	if !status.Valid() {
		return domain.Tracker{}, errors.New("invalid tracker status")
	}
	update := "SET #s = :s, resumed_at = :at REMOVE paused_by, paused_at"
	vals := map[string]types.AttributeValue{":s": &types.AttributeValueMemberS{Value: string(status)}, ":at": timeKey(at)}
	if status == domain.TrackerPaused {
		update = "SET #s = :s, paused_by = :by, paused_at = :at"
		vals[":by"] = &types.AttributeValueMemberS{Value: by}
	}
	out, err := s.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName:                           aws.String(s.table),
		Key:                                 trackerKey(trackerID),
		UpdateExpression:                    aws.String(update),
		ConditionExpression:                 aws.String("attribute_exists(tracker_id) AND #s <> :s"),
		ExpressionAttributeNames:            map[string]string{"#s": "status"},
		ExpressionAttributeValues:           vals,
		ReturnValues:                        types.ReturnValueAllNew,
		ReturnValuesOnConditionCheckFailure: types.ReturnValuesOnConditionCheckFailureAllOld,
	})
	var item map[string]types.AttributeValue
	if err == nil {
		item = out.Attributes
	} else {
		var ccf *types.ConditionalCheckFailedException
		if !errors.As(err, &ccf) {
			return domain.Tracker{}, err
		}
		if len(ccf.Item) == 0 {
			return domain.Tracker{}, ErrNotFound
		}
		item = ccf.Item // already in that status
	}
	var t domain.Tracker
	if err := attributevalue.UnmarshalMap(item, &t); err != nil {
		return domain.Tracker{}, err
	}
	return t, nil
}
