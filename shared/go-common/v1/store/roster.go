package store

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
)

// ReleaseRoster frees a caregiver's place on a team's roster, once they have
// left it or been removed (PRD, Care team; ADR 0012, Membership, amended in
// the Team endpoints gate), on every receiver of the team, archived or not:
//
//   - every coverage schedule naming them ends today in the receiver's zone
//     (one already ending sooner is left alone);
//   - every assignment of theirs still ahead — not yet begun — is removed,
//     the way an admin removes one: deleted if made by hand, kept as a
//     removed row if a rule made it, so the rule does not make it again;
//   - one they are part-way through ends now, so nobody reads them as on
//     duty after they can no longer open the app;
//   - everything already past stays, still saying who was responsible.
//
// What it changes is stamped as changed by the caregiver leaving. It is safe
// to repeat. The generator makes nothing more for them: it makes
// assignments only for someone still on the team.
func (s *Stores) ReleaseRoster(ctx context.Context, teamID, userID string, now time.Time) error {
	for _, status := range []domain.ReceiverStatus{domain.ReceiverActive, domain.ReceiverArchived} {
		rs, err := s.Receivers.ListByTeam(ctx, teamID, status)
		if err != nil {
			return fmt.Errorf("releasing %s's roster on team %s: listing receivers: %w", userID, teamID, err)
		}
		for _, rc := range rs {
			if err := s.releaseReceiverRoster(ctx, rc, userID, now); err != nil {
				return fmt.Errorf("releasing %s's roster on receiver %s: %w", userID, rc.ReceiverID, err)
			}
		}
	}
	return nil
}

func (s *Stores) releaseReceiverRoster(ctx context.Context, rc domain.Receiver, userID string, now time.Time) error {
	loc, err := time.LoadLocation(rc.TimeZone)
	if err != nil {
		return fmt.Errorf("time zone: %w", err)
	}
	local := now.In(loc)
	today := local.Format(time.DateOnly)
	rules, err := s.CoverageSchedules.ListLiveByReceiver(ctx, rc.ReceiverID)
	if err != nil {
		return err
	}
	for _, cs := range rules {
		if cs.UserID != userID {
			continue
		}
		if _, err := s.CoverageSchedules.EndOn(ctx, cs.CoverageScheduleID, today, now); err != nil {
			return err
		}
	}
	as, err := s.Assignments.NotEndedByReceiver(ctx, rc.ReceiverID, now)
	if err != nil {
		return err
	}
	for _, a := range as {
		if a.UserID != userID {
			continue
		}
		if a.StartsAt.Before(now) {
			if _, err := s.Assignments.EndNow(ctx, a, local.Format(domain.LocalDateTimeFormat), userID, now); err != nil {
				return err
			}
			continue
		}
		if err := s.Assignments.Remove(ctx, a, userID, now); err != nil && !errors.Is(err, ErrNotFound) && !errors.Is(err, ErrAssignmentEnded) {
			return err
		}
	}
	return nil
}
