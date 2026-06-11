package store

import (
	"context"
	"errors"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
)

type InvitationStore struct {
	client *dynamodb.Client
	table  string
}

func (s *InvitationStore) Create(ctx context.Context, inv domain.Invitation) error {
	item, err := attributevalue.MarshalMap(inv)
	if err != nil {
		return err
	}
	_, err = s.client.PutItem(ctx, &dynamodb.PutItemInput{
		TableName:                aws.String(s.table),
		Item:                     item,
		ConditionExpression:      aws.String("attribute_not_exists(#tok)"),
		ExpressionAttributeNames: map[string]string{"#tok": "token"},
	})
	return err
}

func (s *InvitationStore) Get(ctx context.Context, token string) (domain.Invitation, error) {
	out, err := s.client.GetItem(ctx, &dynamodb.GetItemInput{
		TableName: aws.String(s.table),
		Key:       map[string]types.AttributeValue{"token": &types.AttributeValueMemberS{Value: token}},
	})
	if err != nil {
		return domain.Invitation{}, err
	}
	if out.Item == nil {
		return domain.Invitation{}, ErrNotFound
	}
	var inv domain.Invitation
	if err := attributevalue.UnmarshalMap(out.Item, &inv); err != nil {
		return domain.Invitation{}, err
	}
	return inv, nil
}

func (s *InvitationStore) ListPendingByEmail(ctx context.Context, email string) ([]domain.Invitation, error) {
	return s.queryPending(ctx, emailIndex, "email", email)
}

func (s *InvitationStore) ListPendingByGroup(ctx context.Context, careGroupID string) ([]domain.Invitation, error) {
	return s.queryPending(ctx, groupIndex, "care_group_id", careGroupID)
}

func (s *InvitationStore) queryPending(ctx context.Context, index, keyAttr, keyVal string) ([]domain.Invitation, error) {
	out, err := s.client.Query(ctx, &dynamodb.QueryInput{
		TableName:                aws.String(s.table),
		IndexName:                aws.String(index),
		KeyConditionExpression:   aws.String("#k = :v"),
		FilterExpression:         aws.String("#s = :pending"),
		ExpressionAttributeNames: map[string]string{"#k": keyAttr, "#s": "status"},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":v":       &types.AttributeValueMemberS{Value: keyVal},
			":pending": &types.AttributeValueMemberS{Value: string(domain.InvitePending)},
		},
	})
	if err != nil {
		return nil, err
	}
	var invs []domain.Invitation
	if err := attributevalue.UnmarshalListOfMaps(out.Items, &invs); err != nil {
		return nil, err
	}
	return invs, nil
}

// Revoke flips a pending invitation to revoked. Returns ErrNotFound if it isn't pending.
func (s *InvitationStore) Revoke(ctx context.Context, token string) error {
	_, err := s.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName:                aws.String(s.table),
		Key:                      map[string]types.AttributeValue{"token": &types.AttributeValueMemberS{Value: token}},
		UpdateExpression:         aws.String("SET #s = :revoked"),
		ConditionExpression:      aws.String("#s = :pending"),
		ExpressionAttributeNames: map[string]string{"#s": "status"},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":revoked": &types.AttributeValueMemberS{Value: string(domain.InviteRevoked)},
			":pending": &types.AttributeValueMemberS{Value: string(domain.InvitePending)},
		},
	})
	if err != nil {
		var ccf *types.ConditionalCheckFailedException
		if errors.As(err, &ccf) {
			return ErrNotFound
		}
		return err
	}
	return nil
}
