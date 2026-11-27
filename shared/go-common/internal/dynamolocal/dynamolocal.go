// Package dynamolocal runs one DynamoDB Local container per test binary.
//
// Starting a container costs seconds while a store test runs in milliseconds, so
// every test in a package shares the container and isolates itself by table name
// instead (see Prefix). testcontainers' reaper removes the container when the test
// binary exits.
package dynamolocal

import (
	"context"
	"fmt"
	"sync"
	"sync/atomic"
	"testing"

	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/wait"
)

var (
	once     sync.Once
	endpoint string
	startErr error
	seq      atomic.Int64
)

// Endpoint returns the URL of this test binary's DynamoDB Local, starting it on
// first use.
func Endpoint(t *testing.T) string {
	t.Helper()
	once.Do(func() {
		ctx := context.Background()
		c, err := testcontainers.GenericContainer(ctx, testcontainers.GenericContainerRequest{
			ContainerRequest: testcontainers.ContainerRequest{
				Image:        "amazon/dynamodb-local:2.5.2",
				ExposedPorts: []string{"8000/tcp"},
				WaitingFor:   wait.ForHTTP("/").WithPort("8000/tcp").WithStatusCodeMatcher(func(int) bool { return true }),
			},
			Started: true,
		})
		if err != nil {
			startErr = fmt.Errorf("start dynamodb-local: %w", err)
			return
		}
		host, err := c.Host(ctx)
		if err != nil {
			startErr = fmt.Errorf("host: %w", err)
			return
		}
		port, err := c.MappedPort(ctx, "8000")
		if err != nil {
			startErr = fmt.Errorf("port: %w", err)
			return
		}
		endpoint = fmt.Sprintf("http://%s:%s", host, port.Port())
	})
	if startErr != nil {
		t.Fatal(startErr)
	}
	return endpoint
}

// Prefix returns a table-name prefix no other test in this binary has used, so
// each test gets its own empty tables in the shared container.
func Prefix() string {
	return fmt.Sprintf("t%d-", seq.Add(1))
}
