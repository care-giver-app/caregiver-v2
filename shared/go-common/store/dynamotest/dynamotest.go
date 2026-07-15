// Package dynamotest spins up DynamoDB Local and creates the B1 tables for tests.
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

	"github.com/care-giver-app/caregiver-v2/shared/go-common/store"
)

// Start launches DynamoDB Local, creates the four tables (with GSIs), and returns
// Stores wired to it. The container is terminated via t.Cleanup.
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
		Users:          "test-user",
		CareGroups:     "test-care-group",
		Memberships:    "test-membership",
		Invitations:    "test-invitation",
		Receivers:      "test-receiver",
		Trackers:       "test-tracker",
		Events:         "test-event",
		ScheduledItems: "test-scheduled-item",
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

	mustCreate(&dynamodb.CreateTableInput{
		TableName:   aws.String(n.Users),
		BillingMode: types.BillingModePayPerRequest,
		AttributeDefinitions: []types.AttributeDefinition{
			{AttributeName: aws.String("user_id"), AttributeType: types.ScalarAttributeTypeS},
			{AttributeName: aws.String("email"), AttributeType: types.ScalarAttributeTypeS},
		},
		KeySchema: []types.KeySchemaElement{
			{AttributeName: aws.String("user_id"), KeyType: types.KeyTypeHash},
		},
		GlobalSecondaryIndexes: []types.GlobalSecondaryIndex{{
			IndexName:  aws.String("email-index"),
			KeySchema:  []types.KeySchemaElement{{AttributeName: aws.String("email"), KeyType: types.KeyTypeHash}},
			Projection: &types.Projection{ProjectionType: types.ProjectionTypeAll},
		}},
	})

	mustCreate(&dynamodb.CreateTableInput{
		TableName:   aws.String(n.CareGroups),
		BillingMode: types.BillingModePayPerRequest,
		AttributeDefinitions: []types.AttributeDefinition{
			{AttributeName: aws.String("care_group_id"), AttributeType: types.ScalarAttributeTypeS},
		},
		KeySchema: []types.KeySchemaElement{
			{AttributeName: aws.String("care_group_id"), KeyType: types.KeyTypeHash},
		},
	})

	mustCreate(&dynamodb.CreateTableInput{
		TableName:   aws.String(n.Memberships),
		BillingMode: types.BillingModePayPerRequest,
		AttributeDefinitions: []types.AttributeDefinition{
			{AttributeName: aws.String("user_id"), AttributeType: types.ScalarAttributeTypeS},
			{AttributeName: aws.String("care_group_id"), AttributeType: types.ScalarAttributeTypeS},
		},
		KeySchema: []types.KeySchemaElement{
			{AttributeName: aws.String("user_id"), KeyType: types.KeyTypeHash},
			{AttributeName: aws.String("care_group_id"), KeyType: types.KeyTypeRange},
		},
		GlobalSecondaryIndexes: []types.GlobalSecondaryIndex{{
			IndexName: aws.String("group-index"),
			KeySchema: []types.KeySchemaElement{
				{AttributeName: aws.String("care_group_id"), KeyType: types.KeyTypeHash},
				{AttributeName: aws.String("user_id"), KeyType: types.KeyTypeRange},
			},
			Projection: &types.Projection{ProjectionType: types.ProjectionTypeAll},
		}},
	})

	mustCreate(&dynamodb.CreateTableInput{
		TableName:   aws.String(n.Invitations),
		BillingMode: types.BillingModePayPerRequest,
		AttributeDefinitions: []types.AttributeDefinition{
			{AttributeName: aws.String("token"), AttributeType: types.ScalarAttributeTypeS},
			{AttributeName: aws.String("care_group_id"), AttributeType: types.ScalarAttributeTypeS},
			{AttributeName: aws.String("email"), AttributeType: types.ScalarAttributeTypeS},
		},
		KeySchema: []types.KeySchemaElement{
			{AttributeName: aws.String("token"), KeyType: types.KeyTypeHash},
		},
		GlobalSecondaryIndexes: []types.GlobalSecondaryIndex{
			{
				IndexName:  aws.String("group-index"),
				KeySchema:  []types.KeySchemaElement{{AttributeName: aws.String("care_group_id"), KeyType: types.KeyTypeHash}},
				Projection: &types.Projection{ProjectionType: types.ProjectionTypeAll},
			},
			{
				IndexName:  aws.String("email-index"),
				KeySchema:  []types.KeySchemaElement{{AttributeName: aws.String("email"), KeyType: types.KeyTypeHash}},
				Projection: &types.Projection{ProjectionType: types.ProjectionTypeAll},
			},
		},
	})

	mustCreate(&dynamodb.CreateTableInput{
		TableName:   aws.String(n.Receivers),
		BillingMode: types.BillingModePayPerRequest,
		AttributeDefinitions: []types.AttributeDefinition{
			{AttributeName: aws.String("receiver_id"), AttributeType: types.ScalarAttributeTypeS},
			{AttributeName: aws.String("care_group_id"), AttributeType: types.ScalarAttributeTypeS},
			{AttributeName: aws.String("created_at"), AttributeType: types.ScalarAttributeTypeS},
		},
		KeySchema: []types.KeySchemaElement{
			{AttributeName: aws.String("receiver_id"), KeyType: types.KeyTypeHash},
		},
		GlobalSecondaryIndexes: []types.GlobalSecondaryIndex{{
			IndexName: aws.String("group-index"),
			KeySchema: []types.KeySchemaElement{
				{AttributeName: aws.String("care_group_id"), KeyType: types.KeyTypeHash},
				{AttributeName: aws.String("created_at"), KeyType: types.KeyTypeRange},
			},
			Projection: &types.Projection{ProjectionType: types.ProjectionTypeAll},
		}},
	})

	mustCreate(&dynamodb.CreateTableInput{
		TableName:   aws.String(n.Trackers),
		BillingMode: types.BillingModePayPerRequest,
		AttributeDefinitions: []types.AttributeDefinition{
			{AttributeName: aws.String("tracker_id"), AttributeType: types.ScalarAttributeTypeS},
			{AttributeName: aws.String("receiver_id"), AttributeType: types.ScalarAttributeTypeS},
			{AttributeName: aws.String("created_at"), AttributeType: types.ScalarAttributeTypeS},
		},
		KeySchema: []types.KeySchemaElement{
			{AttributeName: aws.String("tracker_id"), KeyType: types.KeyTypeHash},
		},
		GlobalSecondaryIndexes: []types.GlobalSecondaryIndex{{
			IndexName: aws.String("receiver-index"),
			KeySchema: []types.KeySchemaElement{
				{AttributeName: aws.String("receiver_id"), KeyType: types.KeyTypeHash},
				{AttributeName: aws.String("created_at"), KeyType: types.KeyTypeRange},
			},
			Projection: &types.Projection{ProjectionType: types.ProjectionTypeAll},
		}},
	})

	mustCreate(&dynamodb.CreateTableInput{
		TableName:   aws.String(n.Events),
		BillingMode: types.BillingModePayPerRequest,
		AttributeDefinitions: []types.AttributeDefinition{
			{AttributeName: aws.String("tracker_id"), AttributeType: types.ScalarAttributeTypeS},
			{AttributeName: aws.String("event_id"), AttributeType: types.ScalarAttributeTypeS},
			{AttributeName: aws.String("occurred_at"), AttributeType: types.ScalarAttributeTypeS},
		},
		KeySchema: []types.KeySchemaElement{
			{AttributeName: aws.String("tracker_id"), KeyType: types.KeyTypeHash},
			{AttributeName: aws.String("event_id"), KeyType: types.KeyTypeRange},
		},
		GlobalSecondaryIndexes: []types.GlobalSecondaryIndex{{
			IndexName: aws.String("time-index"),
			KeySchema: []types.KeySchemaElement{
				{AttributeName: aws.String("tracker_id"), KeyType: types.KeyTypeHash},
				{AttributeName: aws.String("occurred_at"), KeyType: types.KeyTypeRange},
			},
			Projection: &types.Projection{ProjectionType: types.ProjectionTypeAll},
		}},
	})

	mustCreate(&dynamodb.CreateTableInput{
		TableName:   aws.String(n.ScheduledItems),
		BillingMode: types.BillingModePayPerRequest,
		AttributeDefinitions: []types.AttributeDefinition{
			{AttributeName: aws.String("scheduled_item_id"), AttributeType: types.ScalarAttributeTypeS},
			{AttributeName: aws.String("tracker_id"), AttributeType: types.ScalarAttributeTypeS},
			{AttributeName: aws.String("receiver_id"), AttributeType: types.ScalarAttributeTypeS},
			{AttributeName: aws.String("scheduled_for"), AttributeType: types.ScalarAttributeTypeS},
		},
		KeySchema: []types.KeySchemaElement{
			{AttributeName: aws.String("scheduled_item_id"), KeyType: types.KeyTypeHash},
		},
		GlobalSecondaryIndexes: []types.GlobalSecondaryIndex{
			{
				IndexName: aws.String("tracker-index"),
				KeySchema: []types.KeySchemaElement{
					{AttributeName: aws.String("tracker_id"), KeyType: types.KeyTypeHash},
					{AttributeName: aws.String("scheduled_for"), KeyType: types.KeyTypeRange},
				},
				Projection: &types.Projection{ProjectionType: types.ProjectionTypeAll},
			},
			{
				IndexName: aws.String("receiver-index"),
				KeySchema: []types.KeySchemaElement{
					{AttributeName: aws.String("receiver_id"), KeyType: types.KeyTypeHash},
					{AttributeName: aws.String("scheduled_for"), KeyType: types.KeyTypeRange},
				},
				Projection: &types.Projection{ProjectionType: types.ProjectionTypeAll},
			},
		},
	})
}
