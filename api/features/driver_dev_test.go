package features_test

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"testing"
	"time"

	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
)

const devRegion = "us-east-2"

// devDriver runs the features against the deployed dev API with real Cognito
// users. Cognito is driven through the aws CLI rather than the SDK, so the
// suite adds no Cognito module to go.mod; the CLI is already needed to deploy.
// Everything it makes is deleted in the After hook, pass or fail.
type devDriver struct {
	base         string
	poolID       string
	clientID     string
	http         *http.Client
	t            tables
	createdUsers []string // Cognito usernames, recorded the moment each exists
}

func newDevDriver(t *testing.T) *devDriver {
	poolID, clientID := os.Getenv("DEV_USER_POOL_ID"), os.Getenv("DEV_USER_POOL_CLIENT_ID")
	if poolID == "" || clientID == "" {
		t.Fatal("FEATURES_TARGET=dev needs DEV_USER_POOL_ID and DEV_USER_POOL_CLIENT_ID (run it with `make smoke-dev`)")
	}
	base := os.Getenv("DEV_API_BASE")
	if base == "" {
		base = "https://api-v2-dev.caretosher.com"
	}
	cfg, err := awsconfig.LoadDefaultConfig(context.Background(), awsconfig.WithRegion(devRegion))
	if err != nil {
		t.Fatalf("aws config: %v", err)
	}
	return &devDriver{
		base: strings.TrimRight(base, "/"), poolID: poolID, clientID: clientID,
		http: &http.Client{Timeout: 30 * time.Second},
		t: tables{client: dynamodb.NewFromConfig(cfg), names: store.TableNames{
			Users:        "caregiver-dev-v1-user",
			Teams:        "caregiver-dev-v1-team",
			Memberships:  "caregiver-dev-v1-membership",
			Invitations:  "caregiver-dev-v1-invitation",
			Receivers:    "caregiver-dev-v1-receiver",
			Trackers:     "caregiver-dev-v1-tracker",
			Schedules:    "caregiver-dev-v1-schedule",
			Entries:      "caregiver-dev-v1-entry",
			JournalNotes: "caregiver-dev-v1-journal-note",
		}},
	}
}

func (d *devDriver) aws(ctx context.Context, args ...string) (string, error) {
	cmd := exec.CommandContext(ctx, "aws", append(args, "--region", devRegion)...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("aws %s: %v: %s", strings.Join(args[:2], " "), err, strings.TrimSpace(stderr.String()))
	}
	return strings.TrimSpace(stdout.String()), nil
}

func (d *devDriver) newPerson(ctx context.Context, p *person) error {
	password := "Feat-" + strings.ReplaceAll(p.email, "@", "-") + "-aA1"
	sub, err := d.aws(ctx, "cognito-idp", "admin-create-user", "--user-pool-id", d.poolID, "--username", p.email,
		"--message-action", "SUPPRESS",
		"--user-attributes", "Name=email,Value="+p.email, "Name=email_verified,Value=true", "Name=name,Value="+p.label,
		"--query", "User.Attributes[?Name=='sub'].Value | [0]", "--output", "text")
	if err != nil {
		return err
	}
	d.createdUsers = append(d.createdUsers, p.email)
	p.userID = sub
	if _, err := d.aws(ctx, "cognito-idp", "admin-set-user-password", "--user-pool-id", d.poolID,
		"--username", p.email, "--password", password, "--permanent"); err != nil {
		return err
	}
	tok, err := d.aws(ctx, "cognito-idp", "admin-initiate-auth", "--user-pool-id", d.poolID, "--client-id", d.clientID,
		"--auth-flow", "ADMIN_USER_PASSWORD_AUTH", "--auth-parameters", "USERNAME="+p.email+",PASSWORD="+password,
		"--query", "AuthenticationResult.IdToken", "--output", "text")
	if err != nil {
		return err
	}
	p.token = tok
	return nil
}

func (d *devDriver) call(ctx context.Context, p *person, method, path string, body any) (answer, error) {
	var rdr io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			return answer{}, err
		}
		rdr = bytes.NewReader(b)
	}
	req, err := http.NewRequestWithContext(ctx, method, d.base+path, rdr)
	if err != nil {
		return answer{}, err
	}
	req.Header.Set("Content-Type", "application/json")
	if p != nil {
		req.Header.Set("Authorization", "Bearer "+p.token)
	}
	resp, err := d.http.Do(req)
	if err != nil {
		return answer{}, err
	}
	defer resp.Body.Close()
	b, err := io.ReadAll(resp.Body)
	if err != nil {
		return answer{}, err
	}
	return answer{request: method + " " + path, status: resp.StatusCode, body: b}, nil
}

func (d *devDriver) db() tables { return d.t }

// cleanup deletes every row the scenario made or caused, then every Cognito
// user. It keeps going past failures and reports them all.
func (d *devDriver) cleanup(ctx context.Context, rows []rowKey, _ []*person) error {
	var errs []error
	for _, k := range rows {
		if err := d.t.deleteRow(ctx, k); err != nil {
			errs = append(errs, fmt.Errorf("delete %s %v: %w", k.table, k.key, err))
		}
	}
	for _, u := range d.createdUsers {
		if _, err := d.aws(ctx, "cognito-idp", "admin-delete-user", "--user-pool-id", d.poolID, "--username", u); err != nil {
			errs = append(errs, err)
		}
	}
	d.createdUsers = nil
	return errors.Join(errs...)
}
