// Package dynamotest spins up DynamoDB Local and creates the v1 tables for tests.
// The keys and GSIs match v1TableSpecs in infra/lib/shared-stack.ts.
package dynamotest

import (
	"context"
	"fmt"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/wait"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
)

// Start launches DynamoDB Local, creates the four v1 tables (with GSIs), and
// returns Stores wired to it. The container is terminated via t.Cleanup.
func Start(t *testing.T) *store.Stores {
	t.Helper()
	ctx := context.Background()

	container, err := testcontainers.GenericContainer(ctx, testcontainers.GenericContainerRequest{
		ContainerRequest: testcontainers.ContainerRequest{
			Image:        "amazon/dynamodb-local:2.5.2",
			ExposedPorts: []string{"8000/tcp"},
			WaitingFor:   wait.ForHTTP("/").WithPort("8000/tcp").WithStatusCodeMatcher(func(int) bool { return true }),
		},
		Started: true,
	})
	if err != nil {
		t.Fatalf("start dynamodb-local: %v", err)
	}
	t.Cleanup(func() { _ = container.Terminate(ctx) })

	host, err := container.Host(ctx)
	if err != nil {
		t.Fatalf("host: %v", err)
	}
	port, err := container.MappedPort(ctx, "8000")
	if err != nil {
		t.Fatalf("port: %v", err)
	}
	endpoint := fmt.Sprintf("http://%s:%s", host, port.Port())

	t.Setenv("AWS_ACCESS_KEY_ID", "local")
	t.Setenv("AWS_SECRET_ACCESS_KEY", "local")
	t.Setenv("AWS_REGION", "us-east-2")

	client, err := store.NewClient(ctx, endpoint)
	if err != nil {
		t.Fatalf("client: %v", err)
	}

	names := store.TableNames{
		Users:       "test-v1-user",
		Teams:       "test-v1-team",
		Memberships: "test-v1-membership",
		Invitations: "test-v1-invitation",
	}
	createTables(t, ctx, client, names)
	return store.New(client, names)
}

func createTables(t *testing.T, ctx context.Context, c *dynamodb.Client, n store.TableNames) {
	t.Helper()
	mustCreate := func(in *dynamodb.CreateTableInput) {
		if _, err := c.CreateTable(ctx, in); err != nil {
			t.Fatalf("create table %s: %v", *in.TableName, err)
		}
	}
	s := func(name string) types.AttributeDefinition {
		return types.AttributeDefinition{AttributeName: aws.String(name), AttributeType: types.ScalarAttributeTypeS}
	}
	hash := func(name string) types.KeySchemaElement {
		return types.KeySchemaElement{AttributeName: aws.String(name), KeyType: types.KeyTypeHash}
	}
	rng := func(name string) types.KeySchemaElement {
		return types.KeySchemaElement{AttributeName: aws.String(name), KeyType: types.KeyTypeRange}
	}
	all := &types.Projection{ProjectionType: types.ProjectionTypeAll}

	mustCreate(&dynamodb.CreateTableInput{
		TableName:            aws.String(n.Users),
		BillingMode:          types.BillingModePayPerRequest,
		AttributeDefinitions: []types.AttributeDefinition{s("user_id"), s("email")},
		KeySchema:            []types.KeySchemaElement{hash("user_id")},
		GlobalSecondaryIndexes: []types.GlobalSecondaryIndex{
			{IndexName: aws.String("email-index"), KeySchema: []types.KeySchemaElement{hash("email")}, Projection: all},
		},
	})

	mustCreate(&dynamodb.CreateTableInput{
		TableName:            aws.String(n.Teams),
		BillingMode:          types.BillingModePayPerRequest,
		AttributeDefinitions: []types.AttributeDefinition{s("team_id")},
		KeySchema:            []types.KeySchemaElement{hash("team_id")},
	})

	mustCreate(&dynamodb.CreateTableInput{
		TableName:            aws.String(n.Memberships),
		BillingMode:          types.BillingModePayPerRequest,
		AttributeDefinitions: []types.AttributeDefinition{s("user_id"), s("team_id")},
		KeySchema:            []types.KeySchemaElement{hash("user_id"), rng("team_id")},
		GlobalSecondaryIndexes: []types.GlobalSecondaryIndex{
			{IndexName: aws.String("team-index"), KeySchema: []types.KeySchemaElement{hash("team_id"), rng("user_id")}, Projection: all},
		},
	})

	// The invitation TTL on expires_at is not enabled here: DynamoDB Local does
	// not delete on TTL, and tests rely on expired rows still being present.
	mustCreate(&dynamodb.CreateTableInput{
		TableName:            aws.String(n.Invitations),
		BillingMode:          types.BillingModePayPerRequest,
		AttributeDefinitions: []types.AttributeDefinition{s("code"), s("team_id"), s("email")},
		KeySchema:            []types.KeySchemaElement{hash("code")},
		GlobalSecondaryIndexes: []types.GlobalSecondaryIndex{
			{IndexName: aws.String("team-index"), KeySchema: []types.KeySchemaElement{hash("team_id")}, Projection: all},
			{IndexName: aws.String("email-index"), KeySchema: []types.KeySchemaElement{hash("email")}, Projection: all},
		},
	})
}
