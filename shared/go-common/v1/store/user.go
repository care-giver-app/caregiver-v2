package store

import (
	"context"
	"errors"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
)

type UserStore struct {
	client *dynamodb.Client
	table  string
}

func (s *UserStore) Get(ctx context.Context, userID string) (domain.User, error) {
	return getItem[domain.User](ctx, s.client, s.table,
		map[string]types.AttributeValue{"user_id": &types.AttributeValueMemberS{Value: userID}})
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

// BatchGet returns the users for the given ids, keyed by user_id. Missing ids
// are simply absent from the result.
func (s *UserStore) BatchGet(ctx context.Context, ids []string) (map[string]domain.User, error) {
	return batchGetItems(ctx, s.client, s.table, "user_id", ids, func(u domain.User) string { return u.UserID })
}
