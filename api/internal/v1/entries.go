package v1

import (
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
)

const (
	defaultEntryLimit = 50
	maxEntryLimit     = 100
)

// entryView is the Entry schema.
type entryView struct {
	EntryID      string         `json:"entry_id"`
	TrackerID    string         `json:"tracker_id"`
	State        string         `json:"state"`
	At           string         `json:"at"`
	Values       map[string]any `json:"values"`
	Note         string         `json:"note,omitempty"`
	ByName       string         `json:"by_name,omitempty"`
	ScheduleID   string         `json:"schedule_id,omitempty"`
	ScheduleName string         `json:"schedule_name,omitempty"`
}

// entryPage is the EntryPage schema.
type entryPage struct {
	Entries    []entryView `json:"entries"`
	NextCursor string      `json:"next_cursor,omitempty"`
}

// Entries serves GET /v1/trackers/{trackerId}/entries: logged, skipped and
// unrecorded entries newest first, never ones still to come.
func (h *Trackers) Entries(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	t, rc, ok := loadTracker(w, r, h.stores, r.PathValue("trackerId"))
	if !ok || !requireTeamRole(w, r, h.stores, c, t.TeamID, false) {
		return
	}
	q := r.URL.Query()
	limit := defaultEntryLimit
	if s := q.Get("limit"); s != "" {
		n, err := strconv.Atoi(s)
		if err != nil || n < 1 || n > maxEntryLimit {
			httpx.WriteError(w, http.StatusBadRequest, "limit must be 1-100")
			return
		}
		limit = n
	}
	loc, err := time.LoadLocation(rc.TimeZone)
	if err != nil {
		httpx.ServerError(w, r, err, "receiver time zone invalid", "receiver_id", rc.ReceiverID)
		return
	}
	// from and to are whole days in the receiver's zone, inclusive; nothing
	// after now is listed whatever to says.
	now := h.now().UTC()
	upper := now
	var from *time.Time
	if s := q.Get("to"); s != "" {
		day, err := time.ParseInLocation(time.DateOnly, s, loc)
		if err != nil {
			httpx.WriteError(w, http.StatusBadRequest, "to must be a date (YYYY-MM-DD)")
			return
		}
		if end := day.AddDate(0, 0, 1).Add(-time.Nanosecond); end.Before(upper) {
			upper = end
		}
	}
	if s := q.Get("from"); s != "" {
		day, err := time.ParseInLocation(time.DateOnly, s, loc)
		if err != nil {
			httpx.WriteError(w, http.StatusBadRequest, "from must be a date (YYYY-MM-DD)")
			return
		}
		if to := q.Get("to"); to != "" && s > to {
			httpx.WriteError(w, http.StatusBadRequest, "from must not be after to")
			return
		}
		from = &day
	}
	if from != nil && from.After(upper) {
		// A range wholly in the future holds nothing that may be listed.
		httpx.WriteJSON(w, http.StatusOK, entryPage{Entries: []entryView{}})
		return
	}

	ctx := r.Context()
	entries, next, err := h.stores.Entries.ListByTrackerTimeline(ctx, t.TrackerID, upper, from, int32(limit), q.Get("cursor"))
	if errors.Is(err, store.ErrInvalidCursor) {
		httpx.WriteError(w, http.StatusBadRequest, "invalid cursor")
		return
	} else if err != nil {
		httpx.ServerError(w, r, err, "entry load failed")
		return
	}

	var userIDs, scheduleIDs []string
	for _, e := range entries {
		if id := byUserID(e); id != "" {
			userIDs = append(userIDs, id)
		}
		if e.ScheduleID != "" {
			scheduleIDs = append(scheduleIDs, e.ScheduleID)
		}
	}
	users, err := h.stores.Users.BatchGet(ctx, userIDs)
	if err != nil {
		httpx.ServerError(w, r, err, "caregiver load failed")
		return
	}
	schedules, err := h.stores.Schedules.BatchGet(ctx, scheduleIDs)
	if err != nil {
		httpx.ServerError(w, r, err, "schedule load failed")
		return
	}

	page := entryPage{Entries: make([]entryView, 0, len(entries)), NextCursor: next}
	for _, e := range entries {
		v := entryView{
			EntryID: e.EntryID, TrackerID: e.TrackerID, State: string(e.DisplayState(now)),
			At: apiTime(e.TimelineAt), Values: e.Values, Note: e.Note, ScheduleID: e.ScheduleID,
		}
		if v.Values == nil {
			v.Values = map[string]any{}
		}
		if id := byUserID(e); id != "" {
			v.ByName = caregiverName(users, id)
		}
		if sc, ok := schedules[e.ScheduleID]; ok {
			v.ScheduleName = domain.ScheduleName(sc)
		}
		page.Entries = append(page.Entries, v)
	}
	httpx.WriteJSON(w, http.StatusOK, page)
}

// byUserID is who logged or skipped e, or "" while it is waiting.
func byUserID(e domain.Entry) string {
	switch e.State {
	case domain.EntryLogged:
		return e.LoggedBy
	case domain.EntrySkipped:
		return e.SkippedBy
	}
	return ""
}

// recurrence is the Recurrence schema.
type recurrence struct {
	Freq     string   `json:"freq"`
	Interval int      `json:"interval"`
	ByDay    []string `json:"by_day"`
}

// trackerSchedule is the TrackerSchedule schema.
type trackerSchedule struct {
	ScheduleID      string         `json:"schedule_id"`
	TrackerID       string         `json:"tracker_id"`
	Label           string         `json:"label,omitempty"`
	Name            string         `json:"name"`
	Rule            recurrence     `json:"rule"`
	Time            string         `json:"time"`
	StartsOn        string         `json:"starts_on"`
	EndsOn          string         `json:"ends_on,omitempty"`
	PlannedValues   map[string]any `json:"planned_values"`
	UnrecordedAlert bool           `json:"unrecorded_alert"`
}

// Schedules serves GET /v1/trackers/{trackerId}/schedules, oldest first.
// Removed schedules are not listed.
func (h *Trackers) Schedules(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	t, _, ok := loadTracker(w, r, h.stores, r.PathValue("trackerId"))
	if !ok || !requireTeamRole(w, r, h.stores, c, t.TeamID, false) {
		return
	}
	scs, err := h.stores.Schedules.ListLiveByTracker(r.Context(), t.TrackerID)
	if err != nil {
		httpx.ServerError(w, r, err, "schedule load failed")
		return
	}
	out := make([]trackerSchedule, 0, len(scs))
	for _, sc := range scs {
		v := trackerSchedule{
			ScheduleID: sc.ScheduleID, TrackerID: sc.TrackerID, Label: strings.TrimSpace(sc.Label), Name: domain.ScheduleName(sc),
			Rule: recurrence{Freq: sc.Rule.Freq, Interval: sc.Rule.Interval, ByDay: sc.Rule.ByDay},
			Time: sc.Time, StartsOn: sc.StartsOn, EndsOn: sc.EndsOn,
			PlannedValues: sc.PlannedValues, UnrecordedAlert: sc.UnrecordedAlert,
		}
		if v.Rule.ByDay == nil {
			v.Rule.ByDay = []string{}
		}
		if v.PlannedValues == nil {
			v.PlannedValues = map[string]any{}
		}
		out = append(out, v)
	}
	httpx.WriteJSON(w, http.StatusOK, out)
}
