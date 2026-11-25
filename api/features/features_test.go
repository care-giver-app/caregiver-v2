// Package features_test runs the Gherkin acceptance features in features/ as a
// plain Go test, so `go test ./...` runs them in-process against DynamoDB Local
// (Docker required, like the other suites). FEATURES_TARGET=dev runs the very
// same steps against the deployed dev API instead; see `make smoke-dev`.
package features_test

import (
	"crypto/rand"
	"fmt"
	"math/big"
	"os"
	"testing"

	"github.com/cucumber/godog"
)

func TestFeatures(t *testing.T) {
	var d driver
	// Scenarios tagged @inprocess need what only the in-process driver can do —
	// read the code a new address was sent, or see the feedback that went out —
	// or would send real mail from dev. Dev skips them.
	tags := ""
	switch target := os.Getenv("FEATURES_TARGET"); target {
	case "", "inprocess":
		d = newInProcess(t)
	case "dev":
		d = newDevDriver(t)
		tags = "~@inprocess"
	default:
		t.Fatalf("FEATURES_TARGET=%q: want empty (in-process) or dev", target)
	}

	// Every name and address a run makes carries the run id, so dev runs never
	// collide and leftovers are easy to find.
	runID := "ft" + randomBase36(6)
	t.Logf("features run id: %s", runID)
	scenario := 0

	suite := godog.TestSuite{
		Name: "features",
		ScenarioInitializer: func(sc *godog.ScenarioContext) {
			scenario++
			newWorld(d, fmt.Sprintf("%s%02d", runID, scenario)).register(sc)
		},
		Options: &godog.Options{
			Format:   "pretty",
			Paths:    []string{"."}, // every area folder under features/, so a new one is never skipped
			Strict:   true,          // an undefined or pending step fails the run
			Tags:     tags,
			TestingT: t,
		},
	}
	if suite.Run() != 0 {
		t.Fatal("one or more feature scenarios failed; see the output above")
	}
}

func randomBase36(n int) string {
	const alphabet = "0123456789abcdefghijklmnopqrstuvwxyz"
	b := make([]byte, n)
	for i := range b {
		v, err := rand.Int(rand.Reader, big.NewInt(int64(len(alphabet))))
		if err != nil {
			panic(err)
		}
		b[i] = alphabet[v.Int64()]
	}
	return string(b)
}
