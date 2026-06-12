package store

import (
	"context"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
)

type ReceiverStore struct {
	client *dynamodb.Client
	table  string
}

func (s *ReceiverStore) Put(ctx context.Context, r domain.Receiver) error {
	item, err := attributevalue.MarshalMap(r)
	if err != nil {
		return err
	}
	_, err = s.client.PutItem(ctx, &dynamodb.PutItemInput{TableName: aws.String(s.table), Item: item})
	return err
}

func (s *ReceiverStore) Get(ctx context.Context, id string) (domain.Receiver, error) {
	return getItem[domain.Receiver](ctx, s.client, s.table, map[string]types.AttributeValue{
		"receiver_id": &types.AttributeValueMemberS{Value: id},
	})
}

// ListByGroup returns the non-archived receivers in a group, oldest-first.
func (s *ReceiverStore) ListByGroup(ctx context.Context, careGroupID string) ([]domain.Receiver, error) {
	return queryItems[domain.Receiver](ctx, s.client, &dynamodb.QueryInput{
		TableName:              aws.String(s.table),
		IndexName:              aws.String(groupIndex),
		KeyConditionExpression: aws.String("care_group_id = :g"),
		FilterExpression:       aws.String("archived = :f"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":g": &types.AttributeValueMemberS{Value: careGroupID},
			":f": &types.AttributeValueMemberBOOL{Value: false},
		},
	})
}

// Archive soft-deletes a receiver. Get/list filters hide archived rows; events
// and trackers are preserved.
func (s *ReceiverStore) Archive(ctx context.Context, id string) error {
	_, err := s.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName:        aws.String(s.table),
		Key:              map[string]types.AttributeValue{"receiver_id": &types.AttributeValueMemberS{Value: id}},
		UpdateExpression: aws.String("SET archived = :t"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":t": &types.AttributeValueMemberBOOL{Value: true},
		},
		ConditionExpression: aws.String("attribute_exists(receiver_id)"),
	})
	return err
}

// Update overwrites the mutable fields (name, date_of_birth) of an existing
// receiver. The caller has already loaded and authorized the row.
func (s *ReceiverStore) Update(ctx context.Context, r domain.Receiver) error {
	item, err := attributevalue.MarshalMap(r)
	if err != nil {
		return err
	}
	_, err = s.client.PutItem(ctx, &dynamodb.PutItemInput{
		TableName:           aws.String(s.table),
		Item:                item,
		ConditionExpression: aws.String("attribute_exists(receiver_id)"),
	})
	return err
}
