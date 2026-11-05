package store

import (
	"context"

	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
)

type TeamStore struct {
	client *dynamodb.Client
	table  string
}

func (s *TeamStore) Get(ctx context.Context, teamID string) (domain.Team, error) {
	return getItem[domain.Team](ctx, s.client, s.table,
		map[string]types.AttributeValue{"team_id": &types.AttributeValueMemberS{Value: teamID}})
}

// BatchGet returns the teams for the given ids, keyed by team_id. Missing ids
// are simply absent from the result.
func (s *TeamStore) BatchGet(ctx context.Context, ids []string) (map[string]domain.Team, error) {
	return batchGetItems(ctx, s.client, s.table, "team_id", ids, func(t domain.Team) string { return t.TeamID })
}
