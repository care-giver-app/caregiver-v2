package features_test

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"

	"github.com/aws/aws-lambda-go/events"
	"github.com/awslabs/aws-lambda-go-api-proxy/httpadapter"
	"github.com/google/uuid"

	v1 "github.com/care-giver-app/caregiver-v2/api/internal/v1"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store/dynamotest"
)

// inProcess runs the real /v1 handlers against DynamoDB Local, behind the same
// Lambda adapter production uses. A request is built as the API Gateway event
// the JWT authorizer would hand the Lambda, so the real claim extraction runs.
type inProcess struct {
	local   dynamotest.Local
	adapter *httpadapter.HandlerAdapterV2
}

func newInProcess(t *testing.T) *inProcess {
	local := dynamotest.StartLocal(t)
	// The same four routes and authenticator as the /v1 block of cmd/lambda/mux.go.
	authn := v1.NewAuthenticator(local.Stores)
	teams := v1.NewTeams(local.Stores)
	inv := v1.NewInvitations(local.Stores)
	mux := http.NewServeMux()
	mux.Handle("GET /v1/me", authn.Wrap(v1.NewMe(local.Stores)))
	mux.Handle("POST /v1/teams", authn.Wrap(http.HandlerFunc(teams.Create)))
	mux.Handle("GET /v1/me/invitations", authn.Wrap(http.HandlerFunc(inv.Mine)))
	mux.Handle("POST /v1/invitations/redeem", authn.Wrap(http.HandlerFunc(inv.Redeem)))
	return &inProcess{local: local, adapter: httpadapter.NewV2(mux)}
}

func (d *inProcess) newPerson(_ context.Context, p *person) error {
	p.userID = "features-" + uuid.NewString()
	return nil
}

func (d *inProcess) call(ctx context.Context, p *person, method, path string, body any) (answer, error) {
	ev := events.APIGatewayV2HTTPRequest{
		Version:  "2.0",
		RouteKey: "$default",
		RawPath:  path,
		Headers:  map[string]string{"content-type": "application/json"},
		RequestContext: events.APIGatewayV2HTTPRequestContext{
			Stage: "$default",
			HTTP:  events.APIGatewayV2HTTPRequestContextHTTPDescription{Method: method, Path: path},
		},
	}
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			return answer{}, err
		}
		ev.Body = string(b)
	}
	if p != nil {
		// What the API Gateway JWT authorizer passes on from a verified ID token.
		ev.RequestContext.Authorizer = &events.APIGatewayV2HTTPRequestContextAuthorizerDescription{
			JWT: &events.APIGatewayV2HTTPRequestContextAuthorizerJWTDescription{
				Claims: map[string]string{"sub": p.userID, "email": p.email, "name": p.label},
			},
		}
	}
	resp, err := d.adapter.ProxyWithContext(ctx, ev)
	if err != nil {
		return answer{}, err
	}
	return answer{request: method + " " + path, status: resp.StatusCode, body: []byte(resp.Body)}, nil
}

func (d *inProcess) db() tables { return tables{client: d.local.Client, names: d.local.Names} }

func (d *inProcess) cleanup(context.Context, []rowKey, []*person) error { return nil }
