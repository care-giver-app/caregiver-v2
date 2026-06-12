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

type UserStore struct {
	client *dynamodb.Client
	table  string
}

func (s *UserStore) Get(ctx context.Context, userID string) (domain.User, error) {
	out, err := s.client.GetItem(ctx, &dynamodb.GetItemInput{
		TableName: aws.String(s.table),
		Key:       map[string]types.AttributeValue{"user_id": &types.AttributeValueMemberS{Value: userID}},
	})
	if err != nil {
		return domain.User{}, err
	}
	if out.Item == nil {
		return domain.User{}, ErrNotFound
	}
	var u domain.User
	if err := attributevalue.UnmarshalMap(out.Item, &u); err != nil {
		return domain.User{}, err
	}
	return u, nil
}

// GetByEmail looks up a user via the email-index. Returns ErrNotFound if none.
func (s *UserStore) GetByEmail(ctx context.Context, email string) (domain.User, error) {
	out, err := s.client.Query(ctx, &dynamodb.QueryInput{
		TableName:              aws.String(s.table),
		IndexName:              aws.String(emailIndex),
		KeyConditionExpression: aws.String("email = :e"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":e": &types.AttributeValueMemberS{Value: email},
		},
		Limit: aws.Int32(1),
	})
	if err != nil {
		return domain.User{}, err
	}
	if len(out.Items) == 0 {
		return domain.User{}, ErrNotFound
	}
	var u domain.User
	if err := attributevalue.UnmarshalMap(out.Items[0], &u); err != nil {
		return domain.User{}, err
	}
	return u, nil
}

// CreateIfAbsent writes the user only if no row exists for the id. It returns
// created=false (no error) if a row already exists — the idempotent JIT path.
func (s *UserStore) CreateIfAbsent(ctx context.Context, u domain.User) (bool, error) {
	item, err := attributevalue.MarshalMap(u)
	if err != nil {
		return false, err
	}
	_, err = s.client.PutItem(ctx, &dynamodb.PutItemInput{
		TableName:           aws.String(s.table),
		Item:                item,
		ConditionExpression: aws.String("attribute_not_exists(user_id)"),
	})
	if err != nil {
		var ccf *types.ConditionalCheckFailedException
		if errors.As(err, &ccf) {
			return false, nil
		}
		return false, err
	}
	return true, nil
}
