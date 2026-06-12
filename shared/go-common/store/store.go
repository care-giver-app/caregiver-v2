// Package store holds the DynamoDB repositories for the B1 entities.
package store

import (
	"context"
	"errors"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
)

// ErrNotFound is returned by Get methods when no item exists.
var ErrNotFound = errors.New("not found")

// TableNames holds the four B1 table names.
type TableNames struct {
	Users       string
	CareGroups  string
	Memberships string
	Invitations string
}

// Stores aggregates the per-entity repositories and owns cross-table transactions.
type Stores struct {
	client *dynamodb.Client
	names  TableNames

	Users       *UserStore
	CareGroups  *CareGroupStore
	Memberships *MembershipStore
	Invitations *InvitationStore
}

const (
	groupIndex = "group-index"
	emailIndex = "email-index"
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
	}), nil
}
