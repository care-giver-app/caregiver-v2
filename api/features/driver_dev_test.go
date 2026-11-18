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
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	cip "github.com/aws/aws-sdk-go-v2/service/cognitoidentityprovider"
	ciptypes "github.com/aws/aws-sdk-go-v2/service/cognitoidentityprovider/types"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
)

const devRegion = "us-east-2"

// devDriver runs the features against the deployed dev API with real Cognito
// users, made through the Cognito SDK (the aws CLI cost about a second of
// start-up per call, four calls per person). Everything it makes is deleted in the After hook, pass or fail.
type devDriver struct {
	base         string
	poolID       string
	clientID     string
	http         *http.Client
	cognito      *cip.Client
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
		http:    &http.Client{Timeout: 30 * time.Second},
		cognito: cip.NewFromConfig(cfg),
		t: tables{client: dynamodb.NewFromConfig(cfg), names: store.TableNames{
			Users:             "caregiver-dev-v1-user",
			Teams:             "caregiver-dev-v1-team",
			Memberships:       "caregiver-dev-v1-membership",
			Invitations:       "caregiver-dev-v1-invitation",
			Receivers:         "caregiver-dev-v1-receiver",
			CareInstructions:  "caregiver-dev-v1-care-instructions",
			Trackers:          "caregiver-dev-v1-tracker",
			Schedules:         "caregiver-dev-v1-schedule",
			Entries:           "caregiver-dev-v1-entry",
			JournalNotes:      "caregiver-dev-v1-journal-note",
			CoverageSchedules: "caregiver-dev-v1-coverage-schedule",
			Assignments:       "caregiver-dev-v1-assignment",
		}},
	}
}

func (d *devDriver) newPerson(ctx context.Context, p *person) error {
	password := "Feat-" + strings.ReplaceAll(p.email, "@", "-") + "-aA1"
	created, err := d.cognito.AdminCreateUser(ctx, &cip.AdminCreateUserInput{
		UserPoolId:    aws.String(d.poolID),
		Username:      aws.String(p.email),
		MessageAction: ciptypes.MessageActionTypeSuppress,
		UserAttributes: []ciptypes.AttributeType{
			{Name: aws.String("email"), Value: aws.String(p.email)},
			{Name: aws.String("email_verified"), Value: aws.String("true")},
			{Name: aws.String("name"), Value: aws.String(p.label)},
		},
	})
	if err != nil {
		return fmt.Errorf("cognito admin-create-user: %w", err)
	}
	d.createdUsers = append(d.createdUsers, p.email)
	for _, a := range created.User.Attributes {
		if aws.ToString(a.Name) == "sub" {
			p.userID = aws.ToString(a.Value)
		}
	}
	if p.userID == "" {
		return fmt.Errorf("cognito admin-create-user: no sub for %s", p.email)
	}
	if _, err := d.cognito.AdminSetUserPassword(ctx, &cip.AdminSetUserPasswordInput{
		UserPoolId: aws.String(d.poolID), Username: aws.String(p.email),
		Password: aws.String(password), Permanent: true,
	}); err != nil {
		return fmt.Errorf("cognito admin-set-user-password: %w", err)
	}
	auth, err := d.cognito.AdminInitiateAuth(ctx, &cip.AdminInitiateAuthInput{
		UserPoolId: aws.String(d.poolID), ClientId: aws.String(d.clientID),
		AuthFlow:       ciptypes.AuthFlowTypeAdminUserPasswordAuth,
		AuthParameters: map[string]string{"USERNAME": p.email, "PASSWORD": password},
	})
	if err != nil {
		return fmt.Errorf("cognito admin-initiate-auth: %w", err)
	}
	if auth.AuthenticationResult == nil {
		return fmt.Errorf("cognito admin-initiate-auth: challenge %s instead of tokens", auth.ChallengeName)
	}
	p.token = aws.ToString(auth.AuthenticationResult.IdToken)
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
		if _, err := d.cognito.AdminDeleteUser(ctx, &cip.AdminDeleteUserInput{
			UserPoolId: aws.String(d.poolID), Username: aws.String(u),
		}); err != nil {
			errs = append(errs, fmt.Errorf("cognito admin-delete-user %s: %w", u, err))
		}
	}
	d.createdUsers = nil
	return errors.Join(errs...)
}
