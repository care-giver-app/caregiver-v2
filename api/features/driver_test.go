package features_test

import (
	"context"
	"strconv"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
)

// person is someone named in a feature ("Sam"). Their email is generated so
// every scenario, and every dev run, uses addresses nobody else has.
type person struct {
	label  string // as written in the feature, and used as their display name
	email  string
	userID string // the Cognito sub (dev) or a synthesized one (in-process)
	token  string // the Cognito ID token (dev only)
}

// answer is what the API said.
type answer struct {
	request string // "POST /v1/teams", for failure messages
	status  int
	body    []byte
}

// driver is how the steps reach the API. Both drivers run the same steps.
type driver interface {
	// newPerson gives a person an identity: synthesized claims in-process, a
	// real Cognito user in dev.
	newPerson(ctx context.Context, p *person) error
	// call makes one request as p, or as nobody when p is nil.
	call(ctx context.Context, p *person, method, path string, body any) (answer, error)
	// db is direct access to the v1 tables, for rows no endpoint writes yet.
	db() tables
	// cleanup removes everything the scenario made. In-process it does
	// nothing: every scenario's ids are unique within one throwaway container.
	cleanup(ctx context.Context, rows []rowKey, people []*person) error
}

// rowKey names one row a scenario made, so the dev driver can delete it.
type rowKey struct {
	table string
	key   map[string]types.AttributeValue
}

type tables struct {
	client *dynamodb.Client
	names  store.TableNames
}

func s(v string) types.AttributeValue { return &types.AttributeValueMemberS{Value: v} }

func userKey(n store.TableNames, userID string) rowKey {
	return rowKey{n.Users, map[string]types.AttributeValue{"user_id": s(userID)}}
}

func teamKey(n store.TableNames, teamID string) rowKey {
	return rowKey{n.Teams, map[string]types.AttributeValue{"team_id": s(teamID)}}
}

func membershipKey(n store.TableNames, userID, teamID string) rowKey {
	return rowKey{n.Memberships, map[string]types.AttributeValue{"user_id": s(userID), "team_id": s(teamID)}}
}

func invitationKey(n store.TableNames, code string) rowKey {
	return rowKey{n.Invitations, map[string]types.AttributeValue{"code": s(code)}}
}

// put writes v as a raw row, through the store's own marshaler so every time
// is stored at the fixed width the stores read and sort by.
func (t tables) put(ctx context.Context, table string, v any) error {
	item, err := store.MarshalItem(v)
	if err != nil {
		return err
	}
	_, err = t.client.PutItem(ctx, &dynamodb.PutItemInput{TableName: aws.String(table), Item: item})
	return err
}

func (t tables) putInvitation(ctx context.Context, inv domain.Invitation) error {
	return t.put(ctx, t.names.Invitations, inv)
}

func (t tables) putMembership(ctx context.Context, m domain.Membership) error {
	return t.put(ctx, t.names.Memberships, m)
}

func receiverKey(n store.TableNames, id string) rowKey {
	return rowKey{n.Receivers, map[string]types.AttributeValue{"receiver_id": s(id)}}
}

func trackerKey(n store.TableNames, id string) rowKey {
	return rowKey{n.Trackers, map[string]types.AttributeValue{"tracker_id": s(id)}}
}

func scheduleKey(n store.TableNames, id string) rowKey {
	return rowKey{n.Schedules, map[string]types.AttributeValue{"schedule_id": s(id)}}
}

func entryKey(n store.TableNames, id string) rowKey {
	return rowKey{n.Entries, map[string]types.AttributeValue{"entry_id": s(id)}}
}

// stores reads the tables through the real v1 stores, for what no endpoint
// shows yet (the occurrences still to come, which Coming up will show).
func (t tables) stores() *store.Stores { return store.New(t.client, t.names) }

func (t tables) update(ctx context.Context, k rowKey, expr string, names map[string]string, values map[string]types.AttributeValue) error {
	_, err := t.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName:                 aws.String(k.table),
		Key:                       k.key,
		UpdateExpression:          aws.String(expr),
		ExpressionAttributeNames:  names,
		ExpressionAttributeValues: values,
	})
	return err
}

// closeAccount does what closing an account does to the user row: the person
// goes (name and address removed), the row stays, marked closed.
func (t tables) closeAccount(ctx context.Context, userID string, now time.Time) error {
	return t.update(ctx, userKey(t.names, userID),
		"SET #s = :closed, #n = :empty, closed_at = :now REMOVE email",
		map[string]string{"#s": "status", "#n": "name"},
		map[string]types.AttributeValue{
			":closed": s(string(domain.UserClosed)), ":empty": s(""), ":now": s(now.UTC().Format(store.TimeFormat)),
		})
}

// closeTeam archives a team, which is what "Close this care team" does.
func (t tables) closeTeam(ctx context.Context, teamID, by string, now time.Time) error {
	return t.update(ctx, teamKey(t.names, teamID),
		"SET #s = :archived, archived_by = :by, archived_at = :now",
		map[string]string{"#s": "status"},
		map[string]types.AttributeValue{
			":archived": s(string(domain.TeamArchived)), ":by": s(by), ":now": s(now.UTC().Format(store.TimeFormat)),
		})
}

func (t tables) setInvitationStatus(ctx context.Context, code string, status domain.InvitationStatus) error {
	return t.update(ctx, invitationKey(t.names, code), "SET #s = :s",
		map[string]string{"#s": "status"}, map[string]types.AttributeValue{":s": s(string(status))})
}

func (t tables) setInvitationExpiry(ctx context.Context, code string, at time.Time) error {
	return t.update(ctx, invitationKey(t.names, code), "SET expires_at = :e", nil,
		map[string]types.AttributeValue{":e": &types.AttributeValueMemberN{Value: strconv.FormatInt(at.Unix(), 10)}})
}

func (t tables) deleteRow(ctx context.Context, k rowKey) error {
	_, err := t.client.DeleteItem(ctx, &dynamodb.DeleteItemInput{TableName: aws.String(k.table), Key: k.key})
	return err
}
