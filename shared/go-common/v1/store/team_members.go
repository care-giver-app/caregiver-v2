package store

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
)

var (
	// ErrLastAdmin is returned when a change would leave a team with no admin.
	ErrLastAdmin = errors.New("a care team always has an admin")
	// ErrNotLastCaregiver is returned by CloseTeam when anyone else is still
	// on the team.
	ErrNotLastCaregiver = errors.New("only the last caregiver on a care team may close it")
)

// memberAttempts bounds how many times a role change or removal starts over
// when the team changed between reading it and writing.
const memberAttempts = 3

// ChangeRole sets a member's role and returns the membership as stored. A
// member already in the role is returned unchanged. It returns ErrNotFound if
// they are not on the team and ErrLastAdmin if they are its only admin and
// role is caregiver.
func (s *Stores) ChangeRole(ctx context.Context, teamID, userID string, role domain.Role) (domain.Membership, error) {
	if !role.Valid() {
		return domain.Membership{}, errors.New("invalid role")
	}
	var out domain.Membership
	err := s.changeMember(ctx, teamID, userID, role == domain.RoleCaregiver, func(target domain.Membership) (*types.TransactWriteItem, bool) {
		out = target
		if target.Role == role {
			return nil, true
		}
		out.Role = role
		return &types.TransactWriteItem{Update: &types.Update{
			TableName:                aws.String(s.names.Memberships),
			Key:                      membershipKey(userID, teamID),
			UpdateExpression:         aws.String("SET #r = :new"),
			ConditionExpression:      aws.String("#r = :old"),
			ExpressionAttributeNames: map[string]string{"#r": "role"},
			ExpressionAttributeValues: map[string]types.AttributeValue{
				":new": str(string(role)), ":old": str(string(target.Role)),
			},
		}}, false
	})
	return out, err
}

// RemoveMember deletes a member's membership: an admin removing them, or
// their leaving. It returns ErrNotFound if they are not on the team and
// ErrLastAdmin if they are its only admin.
func (s *Stores) RemoveMember(ctx context.Context, teamID, userID string) error {
	return s.changeMember(ctx, teamID, userID, true, func(target domain.Membership) (*types.TransactWriteItem, bool) {
		return &types.TransactWriteItem{Delete: &types.Delete{
			TableName:                aws.String(s.names.Memberships),
			Key:                      membershipKey(userID, teamID),
			ConditionExpression:      aws.String("#r = :old"),
			ExpressionAttributeNames: map[string]string{"#r": "role"},
			ExpressionAttributeValues: map[string]types.AttributeValue{
				":old": str(string(target.Role)),
			},
		}}, false
	})
}

// changeMember applies the write that build makes for the target's membership
// as read. When losesAdmin is true and the target is an admin, the team must
// keep another admin: the write goes in one transaction with a check that some
// other admin, as read, is still an admin, so two admins demoting or removing
// each other at once cannot both succeed. Each write is also conditional on the
// target's role as read. A refused condition means the team changed since it
// was read, and the attempt starts over from a fresh read. build returns done
// true when there is nothing to write.
func (s *Stores) changeMember(ctx context.Context, teamID, userID string, losesAdmin bool,
	build func(target domain.Membership) (*types.TransactWriteItem, bool)) error {
	for attempt := 1; ; attempt++ {
		members, err := s.Memberships.ListByTeam(ctx, teamID)
		if err != nil {
			return err
		}
		var target *domain.Membership
		var otherAdmin string
		for i, m := range members {
			if m.UserID == userID {
				target = &members[i]
			} else if m.Role == domain.RoleAdmin && otherAdmin == "" {
				otherAdmin = m.UserID
			}
		}
		if target == nil {
			// The index is eventually consistent; confirm against the table.
			m, err := s.Memberships.Get(ctx, userID, teamID)
			if err != nil {
				return err
			}
			target = &m
		}
		write, done := build(*target)
		if done {
			return nil
		}
		items := []types.TransactWriteItem{*write}
		if losesAdmin && target.Role == domain.RoleAdmin {
			if otherAdmin == "" {
				return ErrLastAdmin
			}
			items = append(items, types.TransactWriteItem{ConditionCheck: &types.ConditionCheck{
				TableName:                 aws.String(s.names.Memberships),
				Key:                       membershipKey(otherAdmin, teamID),
				ConditionExpression:       aws.String("#r = :admin"),
				ExpressionAttributeNames:  map[string]string{"#r": "role"},
				ExpressionAttributeValues: map[string]types.AttributeValue{":admin": str(string(domain.RoleAdmin))},
			}})
		}
		_, err = s.client.TransactWriteItems(ctx, &dynamodb.TransactWriteItemsInput{TransactItems: items})
		if err == nil {
			return nil
		}
		var tce *types.TransactionCanceledException
		if !errors.As(err, &tce) {
			return err
		}
		// A refused condition, or a conflict with a concurrent transaction on
		// the same rows: read the team again and retry.
		if attempt == memberAttempts {
			return fmt.Errorf("team %s changed during each of %d attempts: %w", teamID, memberAttempts, err)
		}
	}
}

// CloseTeam archives the team and deletes the closer's membership, in one
// transaction. It returns ErrNotLastCaregiver when anyone else is on the team,
// ErrNotFound when the closer is not on it or the team is missing or already
// archived.
//
// The check that nobody else is on the team is a read before the write: a
// caregiver redeeming an invitation at the same instant can still join, and is
// then on an archived team, which nobody can reach.
func (s *Stores) CloseTeam(ctx context.Context, teamID, userID string, at time.Time) error {
	members, err := s.Memberships.ListByTeam(ctx, teamID)
	if err != nil {
		return err
	}
	for _, m := range members {
		if m.UserID != userID {
			return ErrNotLastCaregiver
		}
	}
	_, err = s.client.TransactWriteItems(ctx, &dynamodb.TransactWriteItemsInput{
		TransactItems: []types.TransactWriteItem{
			{Update: &types.Update{
				TableName:                aws.String(s.names.Teams),
				Key:                      map[string]types.AttributeValue{"team_id": str(teamID)},
				UpdateExpression:         aws.String("SET #s = :archived, archived_by = :by, archived_at = :at"),
				ConditionExpression:      aws.String("#s = :active"),
				ExpressionAttributeNames: map[string]string{"#s": "status"},
				ExpressionAttributeValues: map[string]types.AttributeValue{
					":archived": str(string(domain.TeamArchived)),
					":active":   str(string(domain.TeamActive)),
					":by":       str(userID),
					":at":       timeKey(at),
				},
			}},
			{Delete: &types.Delete{
				TableName:           aws.String(s.names.Memberships),
				Key:                 membershipKey(userID, teamID),
				ConditionExpression: aws.String("attribute_exists(user_id)"),
			}},
		},
	})
	var tce *types.TransactionCanceledException
	if errors.As(err, &tce) {
		for _, r := range tce.CancellationReasons {
			if conditionFailed(r) {
				return ErrNotFound
			}
		}
	}
	return err
}
