package store_test

import (
	"context"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store/dynamotest"
)

// seed writes v (a domain value, or a map shaped like a migrated row) as a raw
// row, for entities no store method writes yet. Times are stored as the stores
// store them; a map carries whatever strings it holds.
func seed(t *testing.T, l dynamotest.Local, table string, v any) {
	t.Helper()
	item, err := store.MarshalItem(v)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if _, err := l.Client.PutItem(context.Background(), &dynamodb.PutItemInput{TableName: aws.String(table), Item: item}); err != nil {
		t.Fatalf("seed %s: %v", table, err)
	}
}
