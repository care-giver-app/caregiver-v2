package store

import (
	"context"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
)

type ReceiverStore struct {
	client *dynamodb.Client
	table  string
}

func (s *ReceiverStore) Get(ctx context.Context, receiverID string) (domain.Receiver, error) {
	return getItem[domain.Receiver](ctx, s.client, s.table,
		map[string]types.AttributeValue{"receiver_id": &types.AttributeValueMemberS{Value: receiverID}})
}

// ListActiveByTeam returns the team's active receivers, oldest first.
func (s *ReceiverStore) ListActiveByTeam(ctx context.Context, teamID string) ([]domain.Receiver, error) {
	return queryAll[domain.Receiver](ctx, s.client, &dynamodb.QueryInput{
		TableName:                aws.String(s.table),
		IndexName:                aws.String(teamIndex),
		KeyConditionExpression:   aws.String("team_id = :t"),
		FilterExpression:         aws.String("#s = :active"),
		ExpressionAttributeNames: map[string]string{"#s": "status"},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":t":      &types.AttributeValueMemberS{Value: teamID},
			":active": &types.AttributeValueMemberS{Value: string(domain.ReceiverActive)},
		},
		ScanIndexForward: aws.Bool(true),
	})
}
