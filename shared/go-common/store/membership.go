package store

import (
	"context"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
)

type MembershipStore struct {
	client *dynamodb.Client
	table  string
}

func (s *MembershipStore) Put(ctx context.Context, m domain.Membership) error {
	item, err := attributevalue.MarshalMap(m)
	if err != nil {
		return err
	}
	_, err = s.client.PutItem(ctx, &dynamodb.PutItemInput{TableName: aws.String(s.table), Item: item})
	return err
}

func (s *MembershipStore) Get(ctx context.Context, userID, careGroupID string) (domain.Membership, error) {
	out, err := s.client.GetItem(ctx, &dynamodb.GetItemInput{
		TableName: aws.String(s.table),
		Key: map[string]types.AttributeValue{
			"user_id":       &types.AttributeValueMemberS{Value: userID},
			"care_group_id": &types.AttributeValueMemberS{Value: careGroupID},
		},
	})
	if err != nil {
		return domain.Membership{}, err
	}
	if out.Item == nil {
		return domain.Membership{}, ErrNotFound
	}
	var m domain.Membership
	if err := attributevalue.UnmarshalMap(out.Item, &m); err != nil {
		return domain.Membership{}, err
	}
	return m, nil
}

func (s *MembershipStore) ListByUser(ctx context.Context, userID string) ([]domain.Membership, error) {
	out, err := s.client.Query(ctx, &dynamodb.QueryInput{
		TableName:              aws.String(s.table),
		KeyConditionExpression: aws.String("user_id = :u"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":u": &types.AttributeValueMemberS{Value: userID},
		},
	})
	if err != nil {
		return nil, err
	}
	var ms []domain.Membership
	if err := attributevalue.UnmarshalListOfMaps(out.Items, &ms); err != nil {
		return nil, err
	}
	return ms, nil
}

func (s *MembershipStore) ListByGroup(ctx context.Context, careGroupID string) ([]domain.Membership, error) {
	out, err := s.client.Query(ctx, &dynamodb.QueryInput{
		TableName:              aws.String(s.table),
		IndexName:              aws.String(groupIndex),
		KeyConditionExpression: aws.String("care_group_id = :g"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":g": &types.AttributeValueMemberS{Value: careGroupID},
		},
	})
	if err != nil {
		return nil, err
	}
	var ms []domain.Membership
	if err := attributevalue.UnmarshalListOfMaps(out.Items, &ms); err != nil {
		return nil, err
	}
	return ms, nil
}
