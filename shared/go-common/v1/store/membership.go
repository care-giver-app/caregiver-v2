package store

import (
	"context"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
)

type MembershipStore struct {
	client *dynamodb.Client
	table  string
}

func (s *MembershipStore) Get(ctx context.Context, userID, teamID string) (domain.Membership, error) {
	return getItem[domain.Membership](ctx, s.client, s.table, map[string]types.AttributeValue{
		"user_id": &types.AttributeValueMemberS{Value: userID},
		"team_id": &types.AttributeValueMemberS{Value: teamID},
	})
}

// ListByUser returns every team membership the user holds. A user belongs to
// a handful of teams, far below the 1 MB Query page, so one page suffices.
func (s *MembershipStore) ListByUser(ctx context.Context, userID string) ([]domain.Membership, error) {
	return queryItems[domain.Membership](ctx, s.client, &dynamodb.QueryInput{
		TableName:              aws.String(s.table),
		KeyConditionExpression: aws.String("user_id = :u"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":u": &types.AttributeValueMemberS{Value: userID},
		},
	})
}
