package store

import (
	"context"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
)

type ScheduledItemStore struct {
	client *dynamodb.Client
	table  string
}

func scheduledItemKey(id string) map[string]types.AttributeValue {
	return map[string]types.AttributeValue{
		"scheduled_item_id": &types.AttributeValueMemberS{Value: id},
	}
}

func (s *ScheduledItemStore) Put(ctx context.Context, si domain.ScheduledItem) error {
	item, err := attributevalue.MarshalMap(si)
	if err != nil {
		return err
	}
	_, err = s.client.PutItem(ctx, &dynamodb.PutItemInput{TableName: aws.String(s.table), Item: item})
	return err
}

func (s *ScheduledItemStore) Get(ctx context.Context, id string) (domain.ScheduledItem, error) {
	return getItem[domain.ScheduledItem](ctx, s.client, s.table, scheduledItemKey(id))
}

// Update overwrites an existing scheduled item, asserting it still exists.
func (s *ScheduledItemStore) Update(ctx context.Context, si domain.ScheduledItem) error {
	item, err := attributevalue.MarshalMap(si)
	if err != nil {
		return err
	}
	_, err = s.client.PutItem(ctx, &dynamodb.PutItemInput{
		TableName:           aws.String(s.table),
		Item:                item,
		ConditionExpression: aws.String("attribute_exists(scheduled_item_id)"),
	})
	return err
}

func (s *ScheduledItemStore) Delete(ctx context.Context, id string) error {
	_, err := s.client.DeleteItem(ctx, &dynamodb.DeleteItemInput{
		TableName: aws.String(s.table),
		Key:       scheduledItemKey(id),
	})
	return err
}

// listByIndex returns scheduled items soonest-first over scheduled_for on the
// named GSI, paginated by an opaque cursor. from/to (inclusive) bound
// scheduled_for; nil means unbounded.
func (s *ScheduledItemStore) listByIndex(ctx context.Context, index, keyAttr, keyVal string, limit int32, cursor string, from, to *time.Time) ([]domain.ScheduledItem, string, error) {
	keyCond := keyAttr + " = :k"
	vals := map[string]types.AttributeValue{":k": &types.AttributeValueMemberS{Value: keyVal}}
	switch {
	case from != nil && to != nil:
		keyCond += " AND scheduled_for BETWEEN :from AND :to"
		vals[":from"] = &types.AttributeValueMemberS{Value: from.UTC().Format(time.RFC3339Nano)}
		vals[":to"] = &types.AttributeValueMemberS{Value: to.UTC().Format(time.RFC3339Nano)}
	case from != nil:
		keyCond += " AND scheduled_for >= :from"
		vals[":from"] = &types.AttributeValueMemberS{Value: from.UTC().Format(time.RFC3339Nano)}
	case to != nil:
		keyCond += " AND scheduled_for <= :to"
		vals[":to"] = &types.AttributeValueMemberS{Value: to.UTC().Format(time.RFC3339Nano)}
	}

	start, err := DecodeCursor(cursor)
	if err != nil {
		return nil, "", err
	}
	in := &dynamodb.QueryInput{
		TableName:                 aws.String(s.table),
		IndexName:                 aws.String(index),
		KeyConditionExpression:    aws.String(keyCond),
		ExpressionAttributeValues: vals,
		ScanIndexForward:          aws.Bool(true), // soonest first
		ExclusiveStartKey:         start,
	}
	if limit > 0 {
		in.Limit = aws.Int32(limit)
	}
	out, err := s.client.Query(ctx, in)
	if err != nil {
		return nil, "", err
	}
	var items []domain.ScheduledItem
	if err := attributevalue.UnmarshalListOfMaps(out.Items, &items); err != nil {
		return nil, "", err
	}
	next, err := EncodeCursor(out.LastEvaluatedKey)
	if err != nil {
		return nil, "", err
	}
	return items, next, nil
}

func (s *ScheduledItemStore) ListByTracker(ctx context.Context, trackerID string, limit int32, cursor string, from, to *time.Time) ([]domain.ScheduledItem, string, error) {
	return s.listByIndex(ctx, trackerIndex, "tracker_id", trackerID, limit, cursor, from, to)
}

func (s *ScheduledItemStore) ListByReceiver(ctx context.Context, receiverID string, limit int32, cursor string, from, to *time.Time) ([]domain.ScheduledItem, string, error) {
	return s.listByIndex(ctx, receiverIndex, "receiver_id", receiverID, limit, cursor, from, to)
}
