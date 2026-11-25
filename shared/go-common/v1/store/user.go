package store

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
)

type UserStore struct {
	client *dynamodb.Client
	table  string
}

func (s *UserStore) Get(ctx context.Context, userID string) (domain.User, error) {
	return getItem[domain.User](ctx, s.client, s.table,
		map[string]types.AttributeValue{"user_id": &types.AttributeValueMemberS{Value: userID}})
}

// CreateIfAbsent writes the user only if no row exists for the id. It returns
// created=false (no error) if a row already exists — the idempotent JIT path.
func (s *UserStore) CreateIfAbsent(ctx context.Context, u domain.User) (bool, error) {
	item, err := MarshalItem(u)
	if err != nil {
		return false, err
	}
	_, err = s.client.PutItem(ctx, &dynamodb.PutItemInput{
		TableName:           aws.String(s.table),
		Item:                item,
		ConditionExpression: aws.String("attribute_not_exists(user_id)"),
	})
	if err != nil {
		var ccf *types.ConditionalCheckFailedException
		if errors.As(err, &ccf) {
			return false, nil
		}
		return false, err
	}
	return true, nil
}

// BatchGet returns the users for the given ids, keyed by user_id. Missing ids
// are simply absent from the result.
func (s *UserStore) BatchGet(ctx context.Context, ids []string) (map[string]domain.User, error) {
	return batchGetItems(ctx, s.client, s.table, "user_id", ids, func(u domain.User) string { return u.UserID })
}

// UserChange is what Update changes; a nil field is left as it is.
type UserChange struct {
	Name               *string
	EmailNotifications *bool
}

// Update applies the change to an active user and returns the row as stored.
// It returns ErrNotFound when there is no such user or the account is closed.
func (s *UserStore) Update(ctx context.Context, userID string, c UserChange) (domain.User, error) {
	sets := []string{}
	names := map[string]string{"#s": "status"}
	values := map[string]types.AttributeValue{":active": str(string(domain.UserActive))}
	if c.Name != nil {
		sets = append(sets, "#n = :n")
		names["#n"] = "name"
		values[":n"] = str(*c.Name)
	}
	if c.EmailNotifications != nil {
		sets = append(sets, "email_notifications = :en")
		values[":en"] = &types.AttributeValueMemberBOOL{Value: *c.EmailNotifications}
	}
	if len(sets) == 0 {
		return s.Get(ctx, userID)
	}
	out, err := s.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName:                 aws.String(s.table),
		Key:                       userKey(userID),
		UpdateExpression:          aws.String("SET " + strings.Join(sets, ", ")),
		ConditionExpression:       aws.String("attribute_exists(user_id) AND #s = :active"),
		ExpressionAttributeNames:  names,
		ExpressionAttributeValues: values,
		ReturnValues:              types.ReturnValueAllNew,
	})
	var ccf *types.ConditionalCheckFailedException
	if errors.As(err, &ccf) {
		return domain.User{}, ErrNotFound
	} else if err != nil {
		return domain.User{}, err
	}
	var u domain.User
	if err := attributevalue.UnmarshalMap(out.Attributes, &u); err != nil {
		return domain.User{}, err
	}
	return u, nil
}

// SetEmail copies a confirmed address onto an active user's row. An empty
// address is refused rather than written: an empty string may not be an
// email-index key. It returns ErrNotFound when there is no such active user.
func (s *UserStore) SetEmail(ctx context.Context, userID, email string) error {
	if email == "" {
		return errors.New("email is required")
	}
	_, err := s.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName:                 aws.String(s.table),
		Key:                       userKey(userID),
		UpdateExpression:          aws.String("SET email = :e"),
		ConditionExpression:       aws.String("attribute_exists(user_id) AND #s = :active"),
		ExpressionAttributeNames:  map[string]string{"#s": "status"},
		ExpressionAttributeValues: map[string]types.AttributeValue{":e": str(email), ":active": str(string(domain.UserActive))},
	})
	var ccf *types.ConditionalCheckFailedException
	if errors.As(err, &ccf) {
		return ErrNotFound
	}
	return err
}

// Close marks the account closed: the name and address are removed (which
// drops the row out of the email-index) and the row stays, so everything
// pointing at it reads as a former caregiver. Closing a closed account is a
// no-op that keeps its first closed_at. It returns ErrNotFound when there is
// no such user.
func (s *UserStore) Close(ctx context.Context, userID string, at time.Time) error {
	_, err := s.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName:                aws.String(s.table),
		Key:                      userKey(userID),
		UpdateExpression:         aws.String("SET #s = :closed, #n = :empty, closed_at = :at REMOVE email"),
		ConditionExpression:      aws.String("attribute_exists(user_id) AND #s = :active"),
		ExpressionAttributeNames: map[string]string{"#s": "status", "#n": "name"},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":closed": str(string(domain.UserClosed)), ":active": str(string(domain.UserActive)),
			":empty": str(""), ":at": timeKey(at),
		},
	})
	var ccf *types.ConditionalCheckFailedException
	if !errors.As(err, &ccf) {
		return err
	}
	u, gerr := s.Get(ctx, userID)
	if gerr != nil {
		return gerr
	}
	if u.Status == domain.UserClosed {
		return nil
	}
	return err
}

// IDsByEmail returns the ids of the users whose row holds the address, via
// the eventually consistent email-index. Closed accounts hold none.
func (s *UserStore) IDsByEmail(ctx context.Context, email string) ([]string, error) {
	us, err := queryItems[domain.User](ctx, s.client, &dynamodb.QueryInput{
		TableName:              aws.String(s.table),
		IndexName:              aws.String(emailIndex),
		KeyConditionExpression: aws.String("email = :e"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":e": str(email),
		},
	})
	if err != nil {
		return nil, err
	}
	ids := make([]string, 0, len(us))
	for _, u := range us {
		ids = append(ids, u.UserID)
	}
	return ids, nil
}

func userKey(userID string) map[string]types.AttributeValue {
	return map[string]types.AttributeValue{"user_id": str(userID)}
}
