package store

import (
	"context"
	"errors"
	"strconv"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
)

var (
	// ErrInvitationNotValid is returned by RedeemInvitation when the code does
	// not exist, is no longer pending, or is at or past its expiry.
	ErrInvitationNotValid = errors.New("invitation not valid")
	// ErrAlreadyMember is returned by RedeemInvitation when the user already
	// belongs to the team. The invitation is left pending.
	ErrAlreadyMember = errors.New("already a member")
)

// CreateTeamWithAdmin writes the team and the creator's admin membership
// atomically. The team write is conditional so an id collision fails cleanly
// and nothing is written.
func (s *Stores) CreateTeamWithAdmin(ctx context.Context, t domain.Team, m domain.Membership) error {
	ti, err := MarshalItem(t)
	if err != nil {
		return err
	}
	mi, err := MarshalItem(m)
	if err != nil {
		return err
	}
	_, err = s.client.TransactWriteItems(ctx, &dynamodb.TransactWriteItemsInput{
		TransactItems: []types.TransactWriteItem{
			{Put: &types.Put{
				TableName:           aws.String(s.names.Teams),
				Item:                ti,
				ConditionExpression: aws.String("attribute_not_exists(team_id)"),
			}},
			{Put: &types.Put{TableName: aws.String(s.names.Memberships), Item: mi}},
		},
	})
	return err
}

// RedeemInvitation atomically flips a pending, unexpired invitation to accepted
// and writes the membership. The pending condition makes concurrent redemptions
// safe: exactly one transaction wins. The expiry is checked against now because
// TTL deletion lags by up to days.
//
// A failed invitation condition (missing, not pending, or expired) returns
// ErrInvitationNotValid; otherwise a failed membership condition returns
// ErrAlreadyMember. Any other cancellation (for example TransactionConflict
// under contention) is returned as is.
func (s *Stores) RedeemInvitation(ctx context.Context, code string, m domain.Membership, now time.Time) error {
	mi, err := MarshalItem(m)
	if err != nil {
		return err
	}
	_, err = s.client.TransactWriteItems(ctx, &dynamodb.TransactWriteItemsInput{
		TransactItems: []types.TransactWriteItem{
			{Update: &types.Update{
				TableName:                aws.String(s.names.Invitations),
				Key:                      map[string]types.AttributeValue{"code": &types.AttributeValueMemberS{Value: code}},
				UpdateExpression:         aws.String("SET #s = :accepted"),
				ConditionExpression:      aws.String("#s = :pending AND expires_at > :now"),
				ExpressionAttributeNames: map[string]string{"#s": "status"},
				ExpressionAttributeValues: map[string]types.AttributeValue{
					":accepted": &types.AttributeValueMemberS{Value: string(domain.InviteAccepted)},
					":pending":  &types.AttributeValueMemberS{Value: string(domain.InvitePending)},
					":now":      &types.AttributeValueMemberN{Value: strconv.FormatInt(now.Unix(), 10)},
				},
			}},
			{Put: &types.Put{
				TableName:           aws.String(s.names.Memberships),
				Item:                mi,
				ConditionExpression: aws.String("attribute_not_exists(user_id)"),
			}},
		},
	})
	if err == nil {
		return nil
	}
	var tce *types.TransactionCanceledException
	if !errors.As(err, &tce) {
		return err
	}
	reasons := tce.CancellationReasons
	if len(reasons) > 0 && conditionFailed(reasons[0]) {
		return ErrInvitationNotValid
	}
	if len(reasons) > 1 && conditionFailed(reasons[1]) {
		return ErrAlreadyMember
	}
	return err
}

// conditionFailed reports whether a transaction item was cancelled by its own
// condition expression.
func conditionFailed(r types.CancellationReason) bool {
	return aws.ToString(r.Code) == "ConditionalCheckFailed"
}
