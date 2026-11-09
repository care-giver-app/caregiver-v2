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
	Receivers   string
	Trackers    string
	Schedules   string
	Entries     string
}

// Stores aggregates the per-entity repositories and owns cross-table transactions.
type Stores struct {
	client *dynamodb.Client
	names  TableNames

	Users       *UserStore
	Teams       *TeamStore
	Memberships *MembershipStore
	Invitations *InvitationStore
	Receivers   *ReceiverStore
	Trackers    *TrackerStore
	Schedules   *ScheduleStore
	Entries     *EntryStore
}

const (
	teamIndex     = "team-index"
	emailIndex    = "email-index"
	receiverIndex = "receiver-index"
	trackerIndex  = "tracker-index"
	trackerTime   = "tracker-time"
	openIndex     = "open-index"
	scheduleIndex = "schedule-index"
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
		Receivers:   &ReceiverStore{client: client, table: names.Receivers},
		Trackers:    &TrackerStore{client: client, table: names.Trackers},
		Schedules:   &ScheduleStore{client: client, table: names.Schedules},
		Entries:     &EntryStore{client: client, table: names.Entries},
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
	// Strongly consistent, so a read straight after a write sees it: the
	// generator re-reads a schedule, tracker and receiver to learn of a change
	// that landed while it ran.
	out, err := client.GetItem(ctx, &dynamodb.GetItemInput{TableName: aws.String(table), Key: key, ConsistentRead: aws.Bool(true)})
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

// queryAll runs a Query to the end, following LastEvaluatedKey, and unmarshals
// every item into []T. For lists bounded by family scale (a team's receivers,
// a receiver's trackers), never for an entry history.
func queryAll[T any](ctx context.Context, client *dynamodb.Client, in *dynamodb.QueryInput) ([]T, error) {
	var vs []T
	for {
		out, err := client.Query(ctx, in)
		if err != nil {
			return nil, err
		}
		var page []T
		if err := attributevalue.UnmarshalListOfMaps(out.Items, &page); err != nil {
			return nil, err
		}
		vs = append(vs, page...)
		if len(out.LastEvaluatedKey) == 0 {
			return vs, nil
		}
		in.ExclusiveStartKey = out.LastEvaluatedKey
	}
}

// TimeFormat is how every v1 time is stored: UTC with a fixed nine-digit
// fraction, so that times compare as strings the way they compare as times.
// Several are sort or index keys (created_at, timeline_at, open_at,
// occurrence_at), and RFC3339Nano — the marshaler's default — trims trailing
// zeros, which sorts "…:00.5Z" before "…:00Z". Reads parse it as RFC3339, which
// also accepts the variable-width values written before this format.
const TimeFormat = "2006-01-02T15:04:05.000000000Z"

// timeKey formats t as stored, for key conditions and update values.
func timeKey(t time.Time) types.AttributeValue {
	return &types.AttributeValueMemberS{Value: t.UTC().Format(TimeFormat)}
}

// MarshalItem marshals a v1 row with every time.Time in TimeFormat. Every v1
// write goes through it; tests seeding raw rows use it too.
func MarshalItem(v any) (map[string]types.AttributeValue, error) {
	return attributevalue.MarshalMapWithOptions(v, func(o *attributevalue.EncoderOptions) {
		o.EncodeTime = func(t time.Time) (types.AttributeValue, error) { return timeKey(t), nil }
	})
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
