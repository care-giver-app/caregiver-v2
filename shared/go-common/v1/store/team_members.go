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

// memberBackoff is how long a role change or removal waits before each
// retry, when the team changed between reading it and writing. Its length is
// the number of retries.
var memberBackoff = []time.Duration{50 * time.Millisecond, 100 * time.Millisecond, 200 * time.Millisecond}

// listTeamIndex reads the team's memberships through the team-index. A test
// replaces it to stand in for an index that has not caught up with the table.
var listTeamIndex = func(ctx context.Context, s *Stores, teamID string) ([]domain.Membership, error) {
	return s.Memberships.ListByTeam(ctx, teamID)
}

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
	if err != nil {
		return domain.Membership{}, err
	}
	return out, nil
}

// RemoveMember deletes a member's membership: an admin removing them, or
// their leaving. Their place on the roster goes with it (ReleaseRoster). It
// returns ErrNotFound if they are not on the team and ErrLastAdmin if they are
// its only admin.
func (s *Stores) RemoveMember(ctx context.Context, teamID, userID string, now time.Time) error {
	if err := s.removeMembership(ctx, teamID, userID); err != nil {
		return err
	}
	return s.ReleaseRoster(ctx, teamID, userID, now)
}

// removeMembership deletes the membership, keeping the team's last admin.
func (s *Stores) removeMembership(ctx context.Context, teamID, userID string) error {
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
// as read from the table. When losesAdmin is true and the target is an admin,
// the team must keep another admin: the write goes in one transaction with a
// check that another admin, confirmed against the table, is still an admin, so
// two admins demoting or removing each other at once cannot both succeed. Each
// write is also conditional on the target's role as read. A refused condition
// means the team changed since it was read: if the target is gone it returns
// ErrNotFound, and otherwise it waits briefly and starts over from fresh
// reads. build returns done true when there is nothing to write.
func (s *Stores) changeMember(ctx context.Context, teamID, userID string, losesAdmin bool,
	build func(target domain.Membership) (*types.TransactWriteItem, bool)) error {
	for attempt := 0; ; attempt++ {
		target, err := s.Memberships.Get(ctx, userID, teamID)
		if err != nil {
			return err
		}
		write, done := build(target)
		if done {
			return nil
		}
		items := []types.TransactWriteItem{*write}
		if losesAdmin && target.Role == domain.RoleAdmin {
			otherAdmin, err := s.otherAdmin(ctx, teamID, userID)
			if err != nil {
				return err
			}
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
		// the same rows. A target removed meanwhile can never pass its
		// condition: that is a 404, not a retry.
		if _, gerr := s.Memberships.Get(ctx, userID, teamID); gerr != nil {
			return gerr
		}
		if attempt == len(memberBackoff) {
			return fmt.Errorf("team %s changed during each of %d attempts: %w", teamID, attempt+1, err)
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(memberBackoff[attempt]):
		}
	}
}

// otherAdmin returns an admin of the team other than userID, confirmed by a
// strongly consistent read of their membership, or "" when there is none.
// The team-index only proposes candidates: it is eventually consistent, so
// one it lists as an admin may have just been made a caregiver or removed.
// An admin made so a moment ago may not be listed yet, in which case the
// change is refused with ErrLastAdmin though the team does have another admin;
// trying again shortly succeeds.
func (s *Stores) otherAdmin(ctx context.Context, teamID, userID string) (string, error) {
	members, err := listTeamIndex(ctx, s, teamID)
	if err != nil {
		return "", err
	}
	for _, m := range members {
		if m.UserID == userID || m.Role != domain.RoleAdmin {
			continue
		}
		got, err := s.Memberships.Get(ctx, m.UserID, teamID)
		if errors.Is(err, ErrNotFound) {
			continue
		} else if err != nil {
			return "", err
		}
		if got.Role == domain.RoleAdmin {
			return m.UserID, nil
		}
	}
	return "", nil
}

// CloseTeam archives the team and deletes the closer's membership, in one
// transaction, then deletes every one of its receivers' still-waiting future
// scheduled entries; the receivers themselves keep their status. It returns ErrNotLastCaregiver when anyone else is on the team,
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
	if err != nil {
		return err
	}
	return s.deleteTeamFutureOpen(ctx, teamID, at)
}

// deleteTeamFutureOpen deletes the still-waiting future scheduled entries of
// every receiver on the team, archived or not. Receivers keep their status;
// the generator makes no more for a team that is archived, and takes back any
// it was writing as the team closed.
func (s *Stores) deleteTeamFutureOpen(ctx context.Context, teamID string, now time.Time) error {
	for _, status := range []domain.ReceiverStatus{domain.ReceiverActive, domain.ReceiverArchived} {
		rs, err := s.Receivers.ListByTeam(ctx, teamID, status)
		if err != nil {
			return fmt.Errorf("team %s closed; listing its receivers to clear their scheduled entries: %w", teamID, err)
		}
		for _, rc := range rs {
			if _, err := s.Entries.DeleteFutureOpenForReceiver(ctx, rc.ReceiverID, now); err != nil {
				return fmt.Errorf("team %s closed; clearing receiver %s's scheduled entries: %w", teamID, rc.ReceiverID, err)
			}
		}
	}
	return nil
}
