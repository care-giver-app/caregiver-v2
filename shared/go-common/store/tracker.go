package store

import (
	"context"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
)

type TrackerStore struct {
	client *dynamodb.Client
	table  string
}

func (s *TrackerStore) Put(ctx context.Context, tr domain.Tracker) error {
	item, err := attributevalue.MarshalMap(tr)
	if err != nil {
		return err
	}
	_, err = s.client.PutItem(ctx, &dynamodb.PutItemInput{TableName: aws.String(s.table), Item: item})
	return err
}

func (s *TrackerStore) Get(ctx context.Context, id string) (domain.Tracker, error) {
	return getItem[domain.Tracker](ctx, s.client, s.table, map[string]types.AttributeValue{
		"tracker_id": &types.AttributeValueMemberS{Value: id},
	})
}

// ListByReceiver returns the non-archived trackers for a receiver, oldest-first.
func (s *TrackerStore) ListByReceiver(ctx context.Context, receiverID string) ([]domain.Tracker, error) {
	return queryItems[domain.Tracker](ctx, s.client, &dynamodb.QueryInput{
		TableName:              aws.String(s.table),
		IndexName:              aws.String(receiverIndex),
		KeyConditionExpression: aws.String("receiver_id = :r"),
		FilterExpression:       aws.String("archived = :f"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":r": &types.AttributeValueMemberS{Value: receiverID},
			":f": &types.AttributeValueMemberBOOL{Value: false},
		},
	})
}

func (s *TrackerStore) Archive(ctx context.Context, id string) error {
	_, err := s.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName:        aws.String(s.table),
		Key:              map[string]types.AttributeValue{"tracker_id": &types.AttributeValueMemberS{Value: id}},
		UpdateExpression: aws.String("SET archived = :t"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":t": &types.AttributeValueMemberBOOL{Value: true},
		},
		ConditionExpression: aws.String("attribute_exists(tracker_id)"),
	})
	return err
}

// Update overwrites mutable fields (name/icon/color/fields) of an existing
// tracker. The caller has already loaded and authorized the row, so denormalized
// receiver_id/care_group_id are carried through unchanged.
func (s *TrackerStore) Update(ctx context.Context, tr domain.Tracker) error {
	item, err := attributevalue.MarshalMap(tr)
	if err != nil {
		return err
	}
	_, err = s.client.PutItem(ctx, &dynamodb.PutItemInput{
		TableName:           aws.String(s.table),
		Item:                item,
		ConditionExpression: aws.String("attribute_exists(tracker_id)"),
	})
	return err
}
