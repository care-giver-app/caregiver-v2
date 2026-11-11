package features_test

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
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
	// The same routes and authenticator as the /v1 block of cmd/lambda/mux.go.
	authn := v1.NewAuthenticator(local.Stores)
	teams := v1.NewTeams(local.Stores)
	inv := v1.NewInvitations(local.Stores)
	mux := http.NewServeMux()
	mux.Handle("GET /v1/me", authn.Wrap(v1.NewMe(local.Stores)))
	mux.Handle("POST /v1/teams", authn.Wrap(http.HandlerFunc(teams.Create)))
	mux.Handle("GET /v1/me/invitations", authn.Wrap(http.HandlerFunc(inv.Mine)))
	mux.Handle("POST /v1/invitations/redeem", authn.Wrap(http.HandlerFunc(inv.Redeem)))

	rcv := v1.NewReceivers(local.Stores)
	trk := v1.NewTrackers(local.Stores)
	mux.Handle("GET /v1/teams/{teamId}/receivers", authn.Wrap(http.HandlerFunc(rcv.ListByTeam)))
	mux.Handle("GET /v1/receivers/{receiverId}/trackers", authn.Wrap(http.HandlerFunc(trk.ListByReceiver)))
	mux.Handle("POST /v1/receivers/{receiverId}/trackers", authn.Wrap(http.HandlerFunc(trk.Create)))
	mux.Handle("GET /v1/trackers/{trackerId}", authn.Wrap(http.HandlerFunc(trk.Get)))
	mux.Handle("PUT /v1/trackers/{trackerId}", authn.Wrap(http.HandlerFunc(trk.Edit)))
	mux.Handle("POST /v1/trackers/{trackerId}/pause", authn.Wrap(http.HandlerFunc(trk.Pause)))
	mux.Handle("POST /v1/trackers/{trackerId}/resume", authn.Wrap(http.HandlerFunc(trk.Resume)))
	mux.Handle("GET /v1/trackers/{trackerId}/entries", authn.Wrap(http.HandlerFunc(trk.Entries)))
	mux.Handle("GET /v1/trackers/{trackerId}/schedules", authn.Wrap(http.HandlerFunc(trk.Schedules)))
	mux.Handle("POST /v1/trackers/{trackerId}/schedules", authn.Wrap(http.HandlerFunc(trk.AddSchedule)))
	mux.Handle("PUT /v1/schedules/{scheduleId}", authn.Wrap(http.HandlerFunc(trk.ChangeSchedule)))
	mux.Handle("DELETE /v1/schedules/{scheduleId}", authn.Wrap(http.HandlerFunc(trk.RemoveSchedule)))
	mux.Handle("GET /v1/tracker-templates", authn.Wrap(http.HandlerFunc(v1.NewTemplates().List)))
	home := v1.NewHome(local.Stores)
	mux.Handle("GET /v1/receivers/{receiverId}/attention", authn.Wrap(http.HandlerFunc(home.Attention)))
	mux.Handle("GET /v1/receivers/{receiverId}/coming-up", authn.Wrap(http.HandlerFunc(home.ComingUp)))
	mux.Handle("GET /v1/receivers/{receiverId}/timeline", authn.Wrap(http.HandlerFunc(home.Timeline)))
	mux.Handle("GET /v1/receivers/{receiverId}/waiting", authn.Wrap(http.HandlerFunc(home.Waiting)))
	mux.Handle("GET /v1/entries/{entryId}", authn.Wrap(http.HandlerFunc(home.Entry)))
	mux.Handle("GET /v1/journal-notes/{noteId}", authn.Wrap(http.HandlerFunc(home.JournalNote)))
	return &inProcess{local: local, adapter: httpadapter.NewV2(mux)}
}

func (d *inProcess) newPerson(_ context.Context, p *person) error {
	p.userID = "features-" + uuid.NewString()
	return nil
}

func (d *inProcess) call(ctx context.Context, p *person, method, path string, body any) (answer, error) {
	rawPath, query, _ := strings.Cut(path, "?")
	ev := events.APIGatewayV2HTTPRequest{
		Version:        "2.0",
		RouteKey:       "$default",
		RawPath:        rawPath,
		RawQueryString: query,
		Headers:        map[string]string{"content-type": "application/json"},
		RequestContext: events.APIGatewayV2HTTPRequestContext{
			Stage: "$default",
			HTTP:  events.APIGatewayV2HTTPRequestContextHTTPDescription{Method: method, Path: rawPath},
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
