// Package store holds the DynamoDB repositories for the B1 entities.
package store

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"

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
	CareGroups  string
	Memberships string
	Invitations string
	Receivers   string
	Trackers    string
	Events      string
}

// Stores aggregates the per-entity repositories and owns cross-table transactions.
type Stores struct {
	client *dynamodb.Client
	names  TableNames

	Users       *UserStore
	CareGroups  *CareGroupStore
	Memberships *MembershipStore
	Invitations *InvitationStore
	Receivers   *ReceiverStore
	Trackers    *TrackerStore
	Events      *EventStore
}

const (
	groupIndex    = "group-index"
	emailIndex    = "email-index"
	receiverIndex = "receiver-index"
	timeIndex     = "time-index"
)

// New builds Stores from a DynamoDB client and table names.
func New(client *dynamodb.Client, names TableNames) *Stores {
	return &Stores{
		client:      client,
		names:       names,
		Users:       &UserStore{client: client, table: names.Users},
		CareGroups:  &CareGroupStore{client: client, table: names.CareGroups},
		Memberships: &MembershipStore{client: client, table: names.Memberships},
		Invitations: &InvitationStore{client: client, table: names.Invitations},
		Receivers:   &ReceiverStore{client: client, table: names.Receivers},
		Trackers:    &TrackerStore{client: client, table: names.Trackers},
		Events:      &EventStore{client: client, table: names.Events},
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

// EncodeCursor serializes a DynamoDB LastEvaluatedKey to an opaque base64 string.
// It assumes all key attributes are strings (true for our event keys:
// tracker_id, event_id, occurred_at).
func EncodeCursor(lek map[string]types.AttributeValue) (string, error) {
	if len(lek) == 0 {
		return "", nil
	}
	var m map[string]any
	if err := attributevalue.UnmarshalMap(lek, &m); err != nil {
		return "", err
	}
	b, err := json.Marshal(m)
	if err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

// DecodeCursor reverses EncodeCursor. An empty string decodes to a nil key.
func DecodeCursor(s string) (map[string]types.AttributeValue, error) {
	if s == "" {
		return nil, nil
	}
	b, err := base64.RawURLEncoding.DecodeString(s)
	if err != nil {
		return nil, err
	}
	var m map[string]any
	if err := json.Unmarshal(b, &m); err != nil {
		return nil, err
	}
	return attributevalue.MarshalMap(m)
}
