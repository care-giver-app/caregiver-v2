package v1

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/generate"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
)

// scheduleBody is the NewSchedule schema; ScheduleWrite is the same without
// replace_gap. Pointers tell a required field left out from its zero value.
type scheduleBody struct {
	Label           string         `json:"label"`
	Rule            *recurrence    `json:"rule"`
	Time            string         `json:"time"`
	EndsOn          string         `json:"ends_on"`
	PlannedValues   map[string]any `json:"planned_values"`
	UnrecordedAlert *bool          `json:"unrecorded_alert"`
	ReplaceGap      bool           `json:"replace_gap"`
}

// readSchedule decodes and validates a schedule's Save against its tracker,
// writing 400 and returning false when it is not one. It also returns the
// receiver's today, which a new schedule starts on.
func readSchedule(w http.ResponseWriter, r *http.Request, t domain.Tracker, rc domain.Receiver, now time.Time) (scheduleBody, domain.ScheduleWrite, string, bool) {
	var b scheduleBody
	if err := json.NewDecoder(r.Body).Decode(&b); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid body")
		return b, domain.ScheduleWrite{}, "", false
	}
	if b.Rule == nil || b.UnrecordedAlert == nil {
		httpx.WriteError(w, http.StatusBadRequest, "rule, time, planned_values and unrecorded_alert are required")
		return b, domain.ScheduleWrite{}, "", false
	}
	loc, err := time.LoadLocation(rc.TimeZone)
	if err != nil {
		httpx.ServerError(w, r, err, "receiver time zone invalid", "receiver_id", rc.ReceiverID)
		return b, domain.ScheduleWrite{}, "", false
	}
	today := now.In(loc).Format(time.DateOnly)
	sw, err := domain.ValidateScheduleWrite(domain.ScheduleWrite{
		Label: b.Label, Rule: domain.Rule{Freq: b.Rule.Freq, Interval: b.Rule.Interval, ByDay: b.Rule.ByDay},
		Time: b.Time, EndsOn: b.EndsOn, PlannedValues: b.PlannedValues, UnrecordedAlert: *b.UnrecordedAlert,
	}, t, today)
	if err != nil {
		httpx.WriteError(w, http.StatusBadRequest, err.Error())
		return b, domain.ScheduleWrite{}, "", false
	}
	return b, sw, today, true
}

// generateFromNow writes the schedule's occurrences from now on; the
// generator itself does nothing on a paused tracker or archived receiver.
func (h *Trackers) generateFromNow(ctx context.Context, sc domain.Schedule, t domain.Tracker, rc domain.Receiver, now time.Time) error {
	_, err := generate.Generate(ctx, h.stores, sc, t, rc, now, now)
	return err
}

// removeSchedule removes a schedule and every occurrence of it still waiting.
// It returns store.ErrNotFound if it was already removed.
func (h *Trackers) removeSchedule(ctx context.Context, scheduleID string, now time.Time) error {
	if err := h.stores.Schedules.MarkRemoved(ctx, scheduleID, now); err != nil {
		return err
	}
	_, err := h.stores.Entries.DeleteFutureOpenForSchedule(ctx, scheduleID, now)
	return err
}

// AddSchedule serves POST /v1/trackers/{trackerId}/schedules (A schedule's
// Save, for a new schedule). It starts today in the receiver's zone, and its
// first occurrence is the first at or after now.
func (h *Trackers) AddSchedule(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	t, rc, ok := loadTracker(w, r, h.stores, r.PathValue("trackerId"))
	if !ok || !requireTeamRole(w, r, h.stores, c, t.TeamID, true) {
		return
	}
	now := h.now().UTC()
	b, sw, today, ok := readSchedule(w, r, t, rc, now)
	if !ok {
		return
	}
	if t.GapHours != nil && !b.ReplaceGap {
		httpx.WriteError(w, http.StatusConflict, "this tracker is watched by a gap; a schedule would turn it off")
		return
	}
	sc := domain.Schedule{
		ScheduleID: h.newID(), TrackerID: t.TrackerID, ReceiverID: t.ReceiverID, TeamID: t.TeamID,
		Label: sw.Label, Rule: sw.Rule, Time: sw.Time, StartsOn: today, EndsOn: sw.EndsOn,
		PlannedValues: sw.PlannedValues, UnrecordedAlert: sw.UnrecordedAlert, CreatedBy: c.UserID, CreatedAt: now,
	}
	ctx := r.Context()
	switch err := h.stores.AddSchedule(ctx, sc, b.ReplaceGap); {
	case errors.Is(err, store.ErrTrackerHasGap):
		httpx.WriteError(w, http.StatusConflict, "this tracker is watched by a gap; a schedule would turn it off")
		return
	case errors.Is(err, store.ErrNotFound):
		httpx.WriteError(w, http.StatusNotFound, "not found")
		return
	case err != nil:
		httpx.ServerError(w, r, err, "create failed")
		return
	}
	if err := h.generateFromNow(ctx, sc, t, rc, now); err != nil {
		httpx.ServerError(w, r, err, "schedule generation failed", "schedule_id", sc.ScheduleID)
		return
	}
	httpx.WriteJSON(w, http.StatusCreated, scheduleView(sc))
}

// loadLiveSchedule writes 404 and returns false when the schedule is unknown or
// removed, or its tracker or receiver is gone; otherwise it returns all three.
func loadLiveSchedule(w http.ResponseWriter, r *http.Request, s *store.Stores, scheduleID string) (domain.Schedule, domain.Tracker, domain.Receiver, bool) {
	sc, err := s.Schedules.Get(r.Context(), scheduleID)
	if errors.Is(err, store.ErrNotFound) || (err == nil && sc.RemovedAt != nil) {
		httpx.WriteError(w, http.StatusNotFound, "not found")
		return domain.Schedule{}, domain.Tracker{}, domain.Receiver{}, false
	} else if err != nil {
		httpx.ServerError(w, r, err, "schedule load failed")
		return domain.Schedule{}, domain.Tracker{}, domain.Receiver{}, false
	}
	t, rc, ok := loadTracker(w, r, s, sc.TrackerID)
	return sc, t, rc, ok
}

// ChangeSchedule serves PUT /v1/schedules/{scheduleId} (A schedule's Save, for
// an existing schedule). Its still-waiting future occurrences are replaced by
// ones made from the new rule; nothing logged, skipped or unrecorded moves.
func (h *Trackers) ChangeSchedule(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	sc, t, rc, ok := loadLiveSchedule(w, r, h.stores, r.PathValue("scheduleId"))
	if !ok || !requireTeamRole(w, r, h.stores, c, t.TeamID, true) {
		return
	}
	now := h.now().UTC()
	_, sw, _, ok := readSchedule(w, r, t, rc, now)
	if !ok {
		return
	}
	sc.Label, sc.Rule, sc.Time, sc.EndsOn = sw.Label, sw.Rule, sw.Time, sw.EndsOn
	sc.PlannedValues, sc.UnrecordedAlert = sw.PlannedValues, sw.UnrecordedAlert
	ctx := r.Context()
	stored, err := h.stores.Schedules.Update(ctx, sc)
	if errors.Is(err, store.ErrNotFound) {
		httpx.WriteError(w, http.StatusNotFound, "not found")
		return
	} else if err != nil {
		httpx.ServerError(w, r, err, "update failed")
		return
	}
	if _, err := h.stores.Entries.DeleteFutureOpenForSchedule(ctx, stored.ScheduleID, now); err != nil {
		httpx.ServerError(w, r, err, "update failed")
		return
	}
	if err := h.generateFromNow(ctx, stored, t, rc, now); err != nil {
		httpx.ServerError(w, r, err, "schedule generation failed", "schedule_id", stored.ScheduleID)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, scheduleView(stored))
}

// RemoveSchedule serves DELETE /v1/schedules/{scheduleId} (Remove this
// schedule? — Remove). The row stays, marked removed, so past entries still
// name it.
func (h *Trackers) RemoveSchedule(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	sc, t, _, ok := loadLiveSchedule(w, r, h.stores, r.PathValue("scheduleId"))
	if !ok || !requireTeamRole(w, r, h.stores, c, t.TeamID, true) {
		return
	}
	if err := h.removeSchedule(r.Context(), sc.ScheduleID, h.now().UTC()); errors.Is(err, store.ErrNotFound) {
		httpx.WriteError(w, http.StatusNotFound, "not found")
		return
	} else if err != nil {
		httpx.ServerError(w, r, err, "remove failed")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
