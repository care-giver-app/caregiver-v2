package store

import (
	"context"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
)

type InvitationStore struct {
	client *dynamodb.Client
	table  string
}

// Create writes a new invitation. The put is conditional so a code collision
// fails with a ConditionalCheckFailedException instead of overwriting.
func (s *InvitationStore) Create(ctx context.Context, inv domain.Invitation) error {
	item, err := MarshalItem(inv)
	if err != nil {
		return err
	}
	_, err = s.client.PutItem(ctx, &dynamodb.PutItemInput{
		TableName:           aws.String(s.table),
		Item:                item,
		ConditionExpression: aws.String("attribute_not_exists(code)"),
	})
	return err
}

func (s *InvitationStore) Get(ctx context.Context, code string) (domain.Invitation, error) {
	return getItem[domain.Invitation](ctx, s.client, s.table,
		map[string]types.AttributeValue{"code": &types.AttributeValueMemberS{Value: code}})
}

// ListPendingByEmail returns the pending invitations addressed to email. It
// filters on status only; dropping expired ones (TTL deletion lags) is the
// caller's job.
func (s *InvitationStore) ListPendingByEmail(ctx context.Context, email string) ([]domain.Invitation, error) {
	return queryItems[domain.Invitation](ctx, s.client, &dynamodb.QueryInput{
		TableName:                aws.String(s.table),
		IndexName:                aws.String(emailIndex),
		KeyConditionExpression:   aws.String("email = :e"),
		FilterExpression:         aws.String("#s = :pending"),
		ExpressionAttributeNames: map[string]string{"#s": "status"},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":e":       &types.AttributeValueMemberS{Value: email},
			":pending": &types.AttributeValueMemberS{Value: string(domain.InvitePending)},
		},
	})
}
