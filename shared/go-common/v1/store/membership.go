package store

import (
	"context"
	"errors"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
)

type MembershipStore struct {
	client *dynamodb.Client
	table  string
}

func (s *MembershipStore) Get(ctx context.Context, userID, teamID string) (domain.Membership, error) {
	return getItem[domain.Membership](ctx, s.client, s.table, membershipKey(userID, teamID))
}

// ListByUser returns every team membership the user holds. A user belongs to
// a handful of teams, far below the 1 MB Query page, so one page suffices.
func (s *MembershipStore) ListByUser(ctx context.Context, userID string) ([]domain.Membership, error) {
	return queryItems[domain.Membership](ctx, s.client, &dynamodb.QueryInput{
		TableName:              aws.String(s.table),
		KeyConditionExpression: aws.String("user_id = :u"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":u": &types.AttributeValueMemberS{Value: userID},
		},
	})
}

// ListByTeam returns everyone on the team, via the team-index.
func (s *MembershipStore) ListByTeam(ctx context.Context, teamID string) ([]domain.Membership, error) {
	return queryAll[domain.Membership](ctx, s.client, &dynamodb.QueryInput{
		TableName:              aws.String(s.table),
		IndexName:              aws.String(teamIndex),
		KeyConditionExpression: aws.String("team_id = :t"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":t": &types.AttributeValueMemberS{Value: teamID},
		},
	})
}

// NotificationChoices is which kinds of notification a caregiver wants from
// one team.
type NotificationChoices struct {
	Reminders, RangeAlerts, GapAlerts, UnrecordedAlerts bool
}

// SetNotifications writes the caregiver's own notification choices for the
// team and returns the membership as stored, or ErrNotFound when they are not
// on it.
func (s *MembershipStore) SetNotifications(ctx context.Context, userID, teamID string, n NotificationChoices) (domain.Membership, error) {
	b := func(v bool) types.AttributeValue { return &types.AttributeValueMemberBOOL{Value: v} }
	out, err := s.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName: aws.String(s.table),
		Key:       membershipKey(userID, teamID),
		UpdateExpression: aws.String("SET notify_reminders = :r, notify_range_alerts = :ra, " +
			"notify_gap_alerts = :g, notify_unrecorded_alerts = :u"),
		ConditionExpression: aws.String("attribute_exists(user_id)"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":r": b(n.Reminders), ":ra": b(n.RangeAlerts), ":g": b(n.GapAlerts), ":u": b(n.UnrecordedAlerts),
		},
		ReturnValues: types.ReturnValueAllNew,
	})
	var ccf *types.ConditionalCheckFailedException
	if errors.As(err, &ccf) {
		return domain.Membership{}, ErrNotFound
	} else if err != nil {
		return domain.Membership{}, err
	}
	var m domain.Membership
	if err := attributevalue.UnmarshalMap(out.Attributes, &m); err != nil {
		return domain.Membership{}, err
	}
	return m, nil
}

func membershipKey(userID, teamID string) map[string]types.AttributeValue {
	return map[string]types.AttributeValue{
		"user_id": &types.AttributeValueMemberS{Value: userID},
		"team_id": &types.AttributeValueMemberS{Value: teamID},
	}
}
