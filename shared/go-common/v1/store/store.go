// Package store holds the DynamoDB repositories for the v1 entities, stored in
// the caregiver-{stage}-v1-{entity} tables (docs/adr/0013-*). It sits beside the
// old store package until cutover and imports nothing from it, so the old one
// can be deleted wholesale.
package store

import (
	"context"
	"errors"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
)

// ErrNotFound is returned by Get methods when no item exists.
var ErrNotFound = errors.New("not found")

// TableNames holds every table name the stores need.
type TableNames struct {
	Users       string
	Teams       string
	Memberships string
	Invitations string
}

// Stores aggregates the per-entity repositories and owns cross-table transactions.
type Stores struct {
	client *dynamodb.Client
	names  TableNames

	Users       *UserStore
	Teams       *TeamStore
	Memberships *MembershipStore
	Invitations *InvitationStore
}

const (
	teamIndex  = "team-index"
	emailIndex = "email-index"
)

// New builds Stores from a DynamoDB client and table names.
func New(client *dynamodb.Client, names TableNames) *Stores {
	return &Stores{
		client:      client,
		names:       names,
		Users:       &UserStore{client: client, table: names.Users},
		Teams:       &TeamStore{client: client, table: names.Teams},
		Memberships: &MembershipStore{client: client, table: names.Memberships},
		Invitations: &InvitationStore{client: client, table: names.Invitations},
	}
}

// NewClient builds a DynamoDB client. A non-empty endpoint (tests/local) overrides
// the resolved endpoint.
func NewClient(ctx context.Context, endpoint string) (*dynamodb.Client, error) {
	cfg, err := awsconfig.LoadDefaultConfig(ctx)
	if err != nil {
		return nil, err
	}
	return dynamodb.NewFromConfig(cfg, func(o *dynamodb.Options) {
		if endpoint != "" {
			o.BaseEndpoint = aws.String(endpoint)
		}
		o.APIOptions = append(o.APIOptions, logOps)
	}), nil
}

// getItem fetches a single item by key and unmarshals it into T. Returns
// ErrNotFound when no item exists.
func getItem[T any](ctx context.Context, client *dynamodb.Client, table string, key map[string]types.AttributeValue) (T, error) {
	var zero T
	out, err := client.GetItem(ctx, &dynamodb.GetItemInput{TableName: aws.String(table), Key: key})
	if err != nil {
		return zero, err
	}
	if out.Item == nil {
		return zero, ErrNotFound
	}
	var v T
	if err := attributevalue.UnmarshalMap(out.Item, &v); err != nil {
		return zero, err
	}
	return v, nil
}

// queryItems runs a Query and unmarshals all items into []T.
func queryItems[T any](ctx context.Context, client *dynamodb.Client, in *dynamodb.QueryInput) ([]T, error) {
	out, err := client.Query(ctx, in)
	if err != nil {
		return nil, err
	}
	var vs []T
	if err := attributevalue.UnmarshalListOfMaps(out.Items, &vs); err != nil {
		return nil, err
	}
	return vs, nil
}

// batchGetMax is DynamoDB's limit on keys per BatchGetItem request.
const batchGetMax = 100

// batchGetRetries bounds how many times unprocessed keys are resent.
const batchGetRetries = 5

// batchGetItems fetches items by a single string partition key, keyed in the
// result by that key. It chunks to DynamoDB's 100-key limit, de-duplicates ids
// (BatchGetItem rejects duplicate keys), and resends UnprocessedKeys with a
// short backoff. Missing ids are simply absent from the result.
func batchGetItems[T any](ctx context.Context, client *dynamodb.Client, table, keyAttr string, ids []string, idOf func(T) string) (map[string]T, error) {
	result := make(map[string]T, len(ids))
	seen := make(map[string]bool, len(ids))
	keys := make([]map[string]types.AttributeValue, 0, len(ids))
	for _, id := range ids {
		if seen[id] {
			continue
		}
		seen[id] = true
		keys = append(keys, map[string]types.AttributeValue{keyAttr: &types.AttributeValueMemberS{Value: id}})
	}
	for start := 0; start < len(keys); start += batchGetMax {
		end := min(start+batchGetMax, len(keys))
		pending := keys[start:end]
		for attempt := 0; len(pending) > 0; attempt++ {
			if attempt > batchGetRetries {
				return nil, errors.New("batch get: unprocessed keys remain after retries")
			}
			if attempt > 0 {
				select {
				case <-ctx.Done():
					return nil, ctx.Err()
				case <-time.After(time.Duration(attempt*50) * time.Millisecond):
				}
			}
			out, err := client.BatchGetItem(ctx, &dynamodb.BatchGetItemInput{
				RequestItems: map[string]types.KeysAndAttributes{table: {Keys: pending}},
			})
			if err != nil {
				return nil, err
			}
			for _, item := range out.Responses[table] {
				var v T
				if err := attributevalue.UnmarshalMap(item, &v); err != nil {
					return nil, err
				}
				result[idOf(v)] = v
			}
			pending = out.UnprocessedKeys[table].Keys
		}
	}
	return result, nil
}
