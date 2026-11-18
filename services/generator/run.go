package main

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/generate"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
)

// Summary is what one run did, across every live schedule and every live
// coverage schedule.
type Summary struct {
	Schedules int `json:"schedules"` // live schedules seen
	Skipped   int `json:"skipped"`   // removed, tracker paused, receiver archived, or team closed
	Failed    int `json:"failed"`
	Written   int `json:"written"` // entries created
	Present   int `json:"present"` // entries already there, left as they were

	CoverageSchedules int `json:"coverage_schedules"` // live coverage schedules seen
	// CoverageSkipped counts rules that made nothing: ended, receiver
	// archived, team closed, or caregiver no longer on the team.
	CoverageSkipped    int `json:"coverage_skipped"`
	CoverageFailed     int `json:"coverage_failed"`
	AssignmentsWritten int `json:"assignments_written"`
	AssignmentsPresent int `json:"assignments_present"` // already there, or changed or removed by hand
}

// Run generates every live schedule's occurrences, and every live coverage
// schedule's assignments, from now. One failure is logged and the run moves
// on; Run returns an error at the end if any failed, so the invocation shows
// as failed.
func Run(ctx context.Context, s *store.Stores, log *slog.Logger, now time.Time) (Summary, error) {
	var sum Summary
	schedules, err := s.Schedules.ListLive(ctx)
	if err != nil {
		log.Error("list live schedules failed", "err", err)
		return sum, fmt.Errorf("list live schedules: %w", err)
	}
	rules, err := s.CoverageSchedules.ListLive(ctx)
	if err != nil {
		log.Error("list live coverage schedules failed", "err", err)
		return sum, fmt.Errorf("list live coverage schedules: %w", err)
	}
	// Every team, in one batched read: a closed team's schedules are skipped
	// before anything else of theirs is read.
	teamIDs := make([]string, 0, len(schedules)+len(rules))
	seen := map[string]bool{}
	for _, id := range teamIDsOf(schedules, rules) {
		if !seen[id] {
			seen[id] = true
			teamIDs = append(teamIDs, id)
		}
	}
	teams, err := s.Teams.BatchGet(ctx, teamIDs)
	if err != nil {
		log.Error("load teams failed", "err", err)
		return sum, fmt.Errorf("load teams: %w", err)
	}
	trackers := map[string]domain.Tracker{}
	receivers := map[string]domain.Receiver{}
	for _, sc := range schedules {
		sum.Schedules++
		attrs := []any{"schedule_id", sc.ScheduleID, "tracker_id", sc.TrackerID, "receiver_id", sc.ReceiverID, "team_id", sc.TeamID}
		res, err := runOne(ctx, s, sc, teams, trackers, receivers, now)
		if err != nil {
			sum.Failed++
			log.Error("schedule failed", append(attrs, "err", err)...)
			continue
		}
		if res.Skipped {
			sum.Skipped++
		}
		sum.Written += res.Written
		sum.Present += res.Present
		log.Info("schedule generated", append(attrs,
			"skipped", res.Skipped, "written", res.Written, "present", res.Present, "through", res.Through)...)
	}
	for _, cs := range rules {
		sum.CoverageSchedules++
		attrs := []any{"coverage_schedule_id", cs.CoverageScheduleID, "receiver_id", cs.ReceiverID, "team_id", cs.TeamID}
		res, err := runCoverage(ctx, s, cs, teams, receivers, now)
		if err != nil {
			sum.CoverageFailed++
			log.Error("coverage schedule failed", append(attrs, "err", err)...)
			continue
		}
		if res.Skipped {
			sum.CoverageSkipped++
		}
		sum.AssignmentsWritten += res.Written
		sum.AssignmentsPresent += res.Present
		log.Info("coverage schedule generated", append(attrs,
			"skipped", res.Skipped, "written", res.Written, "present", res.Present, "through", res.Through)...)
	}
	log.Info("run complete", "schedules", sum.Schedules, "skipped", sum.Skipped, "failed", sum.Failed,
		"written", sum.Written, "present", sum.Present,
		"coverage_schedules", sum.CoverageSchedules, "coverage_skipped", sum.CoverageSkipped, "coverage_failed", sum.CoverageFailed,
		"assignments_written", sum.AssignmentsWritten, "assignments_present", sum.AssignmentsPresent)
	if failed := sum.Failed + sum.CoverageFailed; failed > 0 {
		return sum, fmt.Errorf("%d of %d schedules and %d of %d coverage schedules failed",
			sum.Failed, sum.Schedules, sum.CoverageFailed, sum.CoverageSchedules)
	}
	return sum, nil
}

func teamIDsOf(schedules []domain.Schedule, rules []domain.CoverageSchedule) []string {
	ids := make([]string, 0, len(schedules)+len(rules))
	for _, sc := range schedules {
		ids = append(ids, sc.TeamID)
	}
	for _, cs := range rules {
		ids = append(ids, cs.TeamID)
	}
	return ids
}

// receiver loads a receiver through the per-run cache.
func receiver(ctx context.Context, s *store.Stores, id string, receivers map[string]domain.Receiver) (domain.Receiver, error) {
	if rc, ok := receivers[id]; ok {
		return rc, nil
	}
	rc, err := s.Receivers.Get(ctx, id)
	if err != nil {
		return rc, fmt.Errorf("receiver %s: %w", id, err)
	}
	receivers[id] = rc
	return rc, nil
}

// runCoverage skips the rule if its team is closed, and otherwise loads its
// receiver, through the per-run cache, and generates it.
func runCoverage(ctx context.Context, s *store.Stores, cs domain.CoverageSchedule, teams map[string]domain.Team,
	receivers map[string]domain.Receiver, now time.Time) (generate.Result, error) {
	team, ok := teams[cs.TeamID]
	if !ok {
		return generate.Result{}, fmt.Errorf("team %s: %w", cs.TeamID, store.ErrNotFound)
	}
	if team.Status == domain.TeamArchived {
		return generate.Result{Skipped: true}, nil
	}
	rc, err := receiver(ctx, s, cs.ReceiverID, receivers)
	if err != nil {
		return generate.Result{}, err
	}
	return generate.GenerateCoverage(ctx, s, cs, rc, now, now)
}

// runOne skips the schedule if its team is closed, and otherwise loads its
// tracker and receiver, through the per-run caches, and generates it.
func runOne(ctx context.Context, s *store.Stores, sc domain.Schedule, teams map[string]domain.Team,
	trackers map[string]domain.Tracker, receivers map[string]domain.Receiver, now time.Time) (generate.Result, error) {
	team, ok := teams[sc.TeamID]
	if !ok {
		return generate.Result{}, fmt.Errorf("team %s: %w", sc.TeamID, store.ErrNotFound)
	}
	if team.Status == domain.TeamArchived {
		return generate.Result{Skipped: true}, nil
	}
	t, ok := trackers[sc.TrackerID]
	if !ok {
		var err error
		if t, err = s.Trackers.Get(ctx, sc.TrackerID); err != nil {
			return generate.Result{}, fmt.Errorf("tracker %s: %w", sc.TrackerID, err)
		}
		trackers[sc.TrackerID] = t
	}
	rc, err := receiver(ctx, s, sc.ReceiverID, receivers)
	if err != nil {
		return generate.Result{}, err
	}
	return generate.Generate(ctx, s, sc, t, rc, now, now)
}
