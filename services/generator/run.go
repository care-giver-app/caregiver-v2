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

// Summary is what one run did, across every live schedule.
type Summary struct {
	Schedules int `json:"schedules"` // live schedules seen
	Skipped   int `json:"skipped"`   // removed, tracker paused, or receiver archived
	Failed    int `json:"failed"`
	Written   int `json:"written"` // entries created
	Present   int `json:"present"` // entries already there, left as they were
}

// Run generates every live schedule's occurrences from now. One schedule's
// failure is logged and the run moves on; Run returns an error at the end if
// any failed, so the invocation shows as failed.
func Run(ctx context.Context, s *store.Stores, log *slog.Logger, now time.Time) (Summary, error) {
	var sum Summary
	schedules, err := s.Schedules.ListLive(ctx)
	if err != nil {
		log.Error("list live schedules failed", "err", err)
		return sum, fmt.Errorf("list live schedules: %w", err)
	}
	trackers := map[string]domain.Tracker{}
	receivers := map[string]domain.Receiver{}
	for _, sc := range schedules {
		sum.Schedules++
		attrs := []any{"schedule_id", sc.ScheduleID, "tracker_id", sc.TrackerID, "receiver_id", sc.ReceiverID, "team_id", sc.TeamID}
		res, err := runOne(ctx, s, sc, trackers, receivers, now)
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
	log.Info("run complete", "schedules", sum.Schedules, "skipped", sum.Skipped, "failed", sum.Failed,
		"written", sum.Written, "present", sum.Present)
	if sum.Failed > 0 {
		return sum, fmt.Errorf("%d of %d schedules failed", sum.Failed, sum.Schedules)
	}
	return sum, nil
}

// runOne loads the schedule's tracker and receiver, through the per-run
// caches, and generates it.
func runOne(ctx context.Context, s *store.Stores, sc domain.Schedule, trackers map[string]domain.Tracker, receivers map[string]domain.Receiver, now time.Time) (generate.Result, error) {
	t, ok := trackers[sc.TrackerID]
	if !ok {
		var err error
		if t, err = s.Trackers.Get(ctx, sc.TrackerID); err != nil {
			return generate.Result{}, fmt.Errorf("tracker %s: %w", sc.TrackerID, err)
		}
		trackers[sc.TrackerID] = t
	}
	rc, ok := receivers[sc.ReceiverID]
	if !ok {
		var err error
		if rc, err = s.Receivers.Get(ctx, sc.ReceiverID); err != nil {
			return generate.Result{}, fmt.Errorf("receiver %s: %w", sc.ReceiverID, err)
		}
		receivers[sc.ReceiverID] = rc
	}
	return generate.Generate(ctx, s, sc, t, rc, now, now)
}
