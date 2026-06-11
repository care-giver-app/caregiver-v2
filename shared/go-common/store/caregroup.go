package store

import (
	"context"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
)

type CareGroupStore struct {
	client *dynamodb.Client
	table  string
}

func (s *CareGroupStore) Get(ctx context.Context, id string) (domain.CareGroup, error) {
	out, err := s.client.GetItem(ctx, &dynamodb.GetItemInput{
		TableName: aws.String(s.table),
		Key:       map[string]types.AttributeValue{"care_group_id": &types.AttributeValueMemberS{Value: id}},
	})
	if err != nil {
		return domain.CareGroup{}, err
	}
	if out.Item == nil {
		return domain.CareGroup{}, ErrNotFound
	}
	var g domain.CareGroup
	if err := attributevalue.UnmarshalMap(out.Item, &g); err != nil {
		return domain.CareGroup{}, err
	}
	return g, nil
}

// BatchGet returns the care groups for the given ids, keyed by id. Missing ids
// are simply absent from the result.
func (s *CareGroupStore) BatchGet(ctx context.Context, ids []string) (map[string]domain.CareGroup, error) {
	result := make(map[string]domain.CareGroup, len(ids))
	if len(ids) == 0 {
		return result, nil
	}
	keys := make([]map[string]types.AttributeValue, 0, len(ids))
	for _, id := range ids {
		keys = append(keys, map[string]types.AttributeValue{"care_group_id": &types.AttributeValueMemberS{Value: id}})
	}
	out, err := s.client.BatchGetItem(ctx, &dynamodb.BatchGetItemInput{
		RequestItems: map[string]types.KeysAndAttributes{s.table: {Keys: keys}},
	})
	if err != nil {
		return nil, err
	}
	for _, item := range out.Responses[s.table] {
		var g domain.CareGroup
		if err := attributevalue.UnmarshalMap(item, &g); err != nil {
			return nil, err
		}
		result[g.CareGroupID] = g
	}
	return result, nil
}
