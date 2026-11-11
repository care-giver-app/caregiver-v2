package v1

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
)

// Trackers serves the /v1 tracker routes: the list, Add tracker, Tracker
// detail, Edit tracker, pause and resume.
type Trackers struct {
	stores *store.Stores
	now    func() time.Time
	newID  func() string
}

func NewTrackers(s *store.Stores) *Trackers {
	return &Trackers{stores: s, now: time.Now, newID: uuid.NewString}
}

// apiTime is how every /v1 date-time is written.
func apiTime(t time.Time) string { return t.UTC().Format(time.RFC3339) }

func apiTimePtr(t *time.Time) *string {
	if t == nil {
		return nil
	}
	s := apiTime(*t)
	return &s
}

// valueRange is the ValueRange schema.
type valueRange struct {
	Low  *float64 `json:"low,omitempty"`
	High *float64 `json:"high,omitempty"`
}

// choiceOption is the ChoiceOption schema.
type choiceOption struct {
	OptionID string `json:"option_id"`
	Label    string `json:"label"`
	Status   string `json:"status"`
}

// trackerField is the TrackerField schema. Multiple and Options are written
// for choice fields only.
type trackerField struct {
	FieldID  string         `json:"field_id"`
	Label    string         `json:"label"`
	Type     string         `json:"type"`
	Unit     string         `json:"unit,omitempty"`
	Required bool           `json:"required"`
	Status   string         `json:"status"`
	Range    *valueRange    `json:"range,omitempty"`
	Multiple *bool          `json:"multiple,omitempty"`
	Options  []choiceOption `json:"options,omitempty"`
}

// trackerRow is the TrackerRow schema.
type trackerRow struct {
	TrackerID      string  `json:"tracker_id"`
	Name           string  `json:"name"`
	Icon           string  `json:"icon"`
	Color          string  `json:"color"`
	Status         string  `json:"status"`
	LastLoggedAt   *string `json:"last_logged_at,omitempty"`
	PausedAt       *string `json:"paused_at,omitempty"`
	NeedsAttention bool    `json:"needs_attention"`
}

// trackerAttention is the TrackerAttention schema.
type trackerAttention struct {
	Kind         string      `json:"kind"`
	EntryID      string      `json:"entry_id,omitempty"`
	OccurrenceAt *string     `json:"occurrence_at,omitempty"`
	FieldID      string      `json:"field_id,omitempty"`
	Value        *float64    `json:"value,omitempty"`
	Range        *valueRange `json:"range,omitempty"`
	Since        *string     `json:"since,omitempty"`
	GapHours     *int        `json:"gap_hours,omitempty"`
}

// trackerDetail is the TrackerDetail schema.
type trackerDetail struct {
	TrackerID     string             `json:"tracker_id"`
	ReceiverID    string             `json:"receiver_id"`
	TeamID        string             `json:"team_id"`
	Name          string             `json:"name"`
	Icon          string             `json:"icon"`
	Color         string             `json:"color"`
	Status        string             `json:"status"`
	PausedAt      *string            `json:"paused_at,omitempty"`
	Fields        []trackerField     `json:"fields"`
	GapHours      *int               `json:"gap_hours,omitempty"`
	ScheduleCount int                `json:"schedule_count"`
	LastLoggedAt  *string            `json:"last_logged_at,omitempty"`
	Attention     []trackerAttention `json:"attention"`
	CreatedAt     string             `json:"created_at"`
}

func fieldView(f domain.Field) trackerField {
	v := trackerField{
		FieldID: f.FieldID, Label: f.Label, Type: string(f.Type), Unit: f.Unit,
		Required: f.Required, Status: string(f.Status),
	}
	if f.Range != nil {
		v.Range = &valueRange{Low: f.Range.Low, High: f.Range.High}
	}
	if f.Type == domain.FieldChoice {
		multiple := f.Multiple
		v.Multiple = &multiple
		v.Options = make([]choiceOption, 0, len(f.Options))
		for _, o := range f.Options {
			v.Options = append(v.Options, choiceOption{OptionID: o.OptionID, Label: o.Label, Status: string(o.Status)})
		}
	}
	return v
}

func attentionView(a domain.Attention) trackerAttention {
	v := trackerAttention{Kind: string(a.Kind)}
	switch a.Kind {
	case domain.AttentionUnrecorded:
		v.EntryID, v.OccurrenceAt = a.EntryID, apiTimePtr(&a.OccurrenceAt)
	case domain.AttentionOutOfRange:
		value := a.Value
		v.EntryID, v.FieldID, v.Value = a.EntryID, a.FieldID, &value
		v.Range = &valueRange{Low: a.Range.Low, High: a.Range.High}
	case domain.AttentionGap:
		hours := a.GapHours
		v.Since, v.GapHours = apiTimePtr(&a.Since), &hours
	}
	return v
}

// attentionInputs reads what EvaluateAttention needs for one tracker: its
// recent logged entries and its open entries in the unrecorded window.
func attentionInputs(ctx context.Context, s *store.Stores, t domain.Tracker, now time.Time) (logged, open []domain.Entry, err error) {
	if logged, err = s.Entries.RecentLoggedByTracker(ctx, t.TrackerID, store.RecentLoggedLimit); err != nil {
		return nil, nil, err
	}
	open, err = s.Entries.OpenByReceiver(ctx, t.ReceiverID, t.TrackerID, now.Add(-domain.UnrecordedWindow), now)
	return logged, open, err
}

// recentLoggedConcurrency caps how many RecentLoggedByTracker queries
// recentLogged has in flight at once.
const recentLoggedConcurrency = 8

// recentLogged reads each tracker's recent logged entries, keyed by
// tracker_id, one query per tracker run concurrently, at most
// recentLoggedConcurrency at a time.
func recentLogged(ctx context.Context, s *store.Stores, trackers []domain.Tracker) (map[string][]domain.Entry, error) {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	got := make([][]domain.Entry, len(trackers))
	errs := make([]error, len(trackers))
	sem := make(chan struct{}, recentLoggedConcurrency)
	var wg sync.WaitGroup
	for i, t := range trackers {
		wg.Add(1)
		go func(i int, trackerID string) {
			defer wg.Done()
			select {
			case sem <- struct{}{}:
			case <-ctx.Done():
				errs[i] = ctx.Err()
				return
			}
			defer func() { <-sem }()
			got[i], errs[i] = s.Entries.RecentLoggedByTracker(ctx, trackerID, store.RecentLoggedLimit)
			if errs[i] != nil {
				cancel()
			}
		}(i, t.TrackerID)
	}
	wg.Wait()
	if err := errors.Join(errs...); err != nil {
		return nil, err
	}
	logged := make(map[string][]domain.Entry, len(trackers))
	for i, t := range trackers {
		logged[t.TrackerID] = got[i]
	}
	return logged, nil
}

// receiverAttention evaluates each of a receiver's trackers at now against
// its recent logged entries (recentLogged's, keyed by tracker_id), with one
// read of the receiver's open entries serving them all. It returns each
// tracker's EvaluateAttention result keyed by tracker_id.
func receiverAttention(ctx context.Context, s *store.Stores, receiverID string, trackers []domain.Tracker, logged map[string][]domain.Entry, now time.Time) (map[string][]domain.Attention, error) {
	open, err := s.Entries.OpenByReceiver(ctx, receiverID, "", now.Add(-domain.UnrecordedWindow), now)
	if err != nil {
		return nil, err
	}
	openBy := make(map[string][]domain.Entry)
	for _, e := range open {
		openBy[e.TrackerID] = append(openBy[e.TrackerID], e)
	}
	attention := make(map[string][]domain.Attention, len(trackers))
	for _, t := range trackers {
		attention[t.TrackerID] = domain.EvaluateAttention(t, now, logged[t.TrackerID], openBy[t.TrackerID])
	}
	return attention, nil
}

// detail builds the TrackerDetail of t as it stands at now.
func (h *Trackers) detail(ctx context.Context, t domain.Tracker, now time.Time) (trackerDetail, error) {
	count, err := h.stores.Schedules.CountLiveByTracker(ctx, t.TrackerID)
	if err != nil {
		return trackerDetail{}, err
	}
	logged, open, err := attentionInputs(ctx, h.stores, t, now)
	if err != nil {
		return trackerDetail{}, err
	}
	d := trackerDetail{
		TrackerID: t.TrackerID, ReceiverID: t.ReceiverID, TeamID: t.TeamID, Name: t.Name, Icon: t.Icon,
		Color: t.Color, Status: string(t.Status), PausedAt: apiTimePtr(t.PausedAt),
		Fields: make([]trackerField, 0, len(t.Fields)), GapHours: t.GapHours, ScheduleCount: count,
		LastLoggedAt: apiTimePtr(domain.LastLoggedAt(logged)), Attention: []trackerAttention{},
		CreatedAt: apiTime(t.CreatedAt),
	}
	for _, f := range t.Fields {
		d.Fields = append(d.Fields, fieldView(f))
	}
	for _, a := range domain.EvaluateAttention(t, now, logged, open) {
		d.Attention = append(d.Attention, attentionView(a))
	}
	return d, nil
}

func (h *Trackers) writeDetail(w http.ResponseWriter, r *http.Request, status int, t domain.Tracker, now time.Time) {
	d, err := h.detail(r.Context(), t, now)
	if err != nil {
		httpx.ServerError(w, r, err, "tracker load failed")
		return
	}
	httpx.WriteJSON(w, status, d)
}

// ListByReceiver serves GET /v1/receivers/{receiverId}/trackers: every
// tracker, active and paused, by name.
func (h *Trackers) ListByReceiver(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	rc, ok := loadReceiver(w, r, h.stores, r.PathValue("receiverId"))
	if !ok || !requireTeamRole(w, r, h.stores, c, rc.TeamID, false) {
		return
	}
	ctx := r.Context()
	now := h.now().UTC()
	trackers, err := h.stores.Trackers.ListByReceiver(ctx, rc.ReceiverID)
	if err != nil {
		httpx.ServerError(w, r, err, "tracker load failed")
		return
	}
	logged, err := recentLogged(ctx, h.stores, trackers)
	if err != nil {
		httpx.ServerError(w, r, err, "entry load failed")
		return
	}
	attention, err := receiverAttention(ctx, h.stores, rc.ReceiverID, trackers, logged, now)
	if err != nil {
		httpx.ServerError(w, r, err, "entry load failed")
		return
	}
	sort.Slice(trackers, func(i, j int) bool {
		a, b := strings.ToLower(trackers[i].Name), strings.ToLower(trackers[j].Name)
		if a != b {
			return a < b
		}
		return trackers[i].TrackerID < trackers[j].TrackerID
	})
	out := make([]trackerRow, 0, len(trackers))
	for _, t := range trackers {
		out = append(out, trackerRow{
			TrackerID: t.TrackerID, Name: t.Name, Icon: t.Icon, Color: t.Color, Status: string(t.Status),
			LastLoggedAt:   apiTimePtr(domain.LastLoggedAt(logged[t.TrackerID])),
			PausedAt:       apiTimePtr(t.PausedAt),
			NeedsAttention: len(attention[t.TrackerID]) > 0,
		})
	}
	httpx.WriteJSON(w, http.StatusOK, out)
}

// Get serves GET /v1/trackers/{trackerId}.
func (h *Trackers) Get(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	t, _, ok := loadTracker(w, r, h.stores, r.PathValue("trackerId"))
	if !ok || !requireTeamRole(w, r, h.stores, c, t.TeamID, false) {
		return
	}
	h.writeDetail(w, r, http.StatusOK, t, h.now().UTC())
}

// fieldWriteBody is the TrackerFieldWrite schema.
type fieldWriteBody struct {
	FieldID  string `json:"field_id"`
	Label    string `json:"label"`
	Type     string `json:"type"`
	Unit     string `json:"unit"`
	Required bool   `json:"required"`
	Status   string `json:"status"`
	Range    *struct {
		Low  *float64 `json:"low"`
		High *float64 `json:"high"`
	} `json:"range"`
	Multiple bool `json:"multiple"`
	Options  []struct {
		OptionID string `json:"option_id"`
		Label    string `json:"label"`
		Status   string `json:"status"`
	} `json:"options"`
}

func (b fieldWriteBody) domain() domain.FieldWrite {
	w := domain.FieldWrite{
		FieldID: b.FieldID, Label: b.Label, Type: domain.FieldType(b.Type), Unit: b.Unit,
		Required: b.Required, Status: domain.FieldStatus(b.Status), Multiple: b.Multiple,
	}
	if b.Range != nil {
		w.Range = &domain.Range{Low: b.Range.Low, High: b.Range.High}
	}
	for _, o := range b.Options {
		w.Options = append(w.Options, domain.OptionWrite{OptionID: o.OptionID, Label: o.Label, Status: domain.OptionStatus(o.Status)})
	}
	return w
}

// trackerBody is what NewTracker and TrackerChanges share.
type trackerBody struct {
	Name   string           `json:"name"`
	Icon   string           `json:"icon"`
	Color  string           `json:"color"`
	Fields []fieldWriteBody `json:"fields"`
}

// validate checks the name, icon and color, returning the trimmed name and icon.
func (b trackerBody) validate() (name, icon string, err error) {
	if name, err = domain.ValidateTrackerName(b.Name); err != nil {
		return "", "", err
	}
	if icon = strings.TrimSpace(b.Icon); icon == "" {
		return "", "", errors.New("icon is required")
	}
	if err = domain.ValidateColor(b.Color); err != nil {
		return "", "", err
	}
	return name, icon, nil
}

func (b trackerBody) fieldWrites() []domain.FieldWrite {
	ws := make([]domain.FieldWrite, 0, len(b.Fields))
	for _, f := range b.Fields {
		ws = append(ws, f.domain())
	}
	return ws
}

// Create serves POST /v1/receivers/{receiverId}/trackers (Add tracker).
func (h *Trackers) Create(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	rc, ok := loadReceiver(w, r, h.stores, r.PathValue("receiverId"))
	if !ok || !requireTeamRole(w, r, h.stores, c, rc.TeamID, true) {
		return
	}
	var req struct {
		trackerBody
		GapHours *int `json:"gap_hours"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid body")
		return
	}
	now := h.now().UTC()
	name, icon, err := req.validate()
	if err == nil {
		err = domain.ValidateGapHours(req.GapHours)
	}
	var fields []domain.Field
	if err == nil {
		fields, err = domain.NewFields(req.fieldWrites(), now)
	}
	if err != nil {
		httpx.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	t := domain.Tracker{
		TrackerID: h.newID(), ReceiverID: rc.ReceiverID, TeamID: rc.TeamID, Name: name, Icon: icon,
		Color: req.Color, Fields: fields, GapHours: req.GapHours, Status: domain.TrackerActive,
		CreatedBy: c.UserID, CreatedAt: now,
	}
	if err := h.stores.Trackers.Create(r.Context(), t); err != nil {
		httpx.ServerError(w, r, err, "create failed")
		return
	}
	h.writeDetail(w, r, http.StatusCreated, t, now)
}

// nullableInt is a JSON integer that may be null, remembering whether it was
// sent at all: TrackerChanges requires gap_hours, and null turns the gap off.
type nullableInt struct {
	Set   bool
	Value *int
}

func (n *nullableInt) UnmarshalJSON(b []byte) error {
	n.Set = true
	if bytes.Equal(b, []byte("null")) {
		n.Value = nil
		return nil
	}
	return json.Unmarshal(b, &n.Value)
}

// Edit serves PUT /v1/trackers/{trackerId} (Edit tracker's Save). It is
// allowed on a paused tracker.
func (h *Trackers) Edit(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	t, _, ok := loadTracker(w, r, h.stores, r.PathValue("trackerId"))
	if !ok || !requireTeamRole(w, r, h.stores, c, t.TeamID, true) {
		return
	}
	var req struct {
		trackerBody
		GapHours        nullableInt `json:"gap_hours"`
		RemoveSchedules bool        `json:"remove_schedules"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid body")
		return
	}
	if !req.GapHours.Set {
		httpx.WriteError(w, http.StatusBadRequest, "gap_hours is required; null turns the gap off")
		return
	}
	ctx := r.Context()
	now := h.now().UTC()
	name, icon, err := req.validate()
	if err == nil {
		err = domain.ValidateGapHours(req.GapHours.Value)
	}
	var fields []domain.Field
	if err == nil {
		fields, err = domain.ApplyFieldChanges(t.Fields, req.fieldWrites(), now)
	}
	if err != nil {
		httpx.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	if req.GapHours.Value != nil {
		scs, err := h.stores.Schedules.ListLiveByTracker(ctx, t.TrackerID)
		if err != nil {
			httpx.ServerError(w, r, err, "schedule load failed")
			return
		}
		if len(scs) > 0 && !req.RemoveSchedules {
			httpx.WriteError(w, http.StatusConflict, "this tracker has schedules; a gap would remove them")
			return
		}
		// Confirmed: every schedule goes as Remove this schedule? would take it.
		for _, sc := range scs {
			if err := h.removeSchedule(ctx, sc.ScheduleID, now); err != nil {
				httpx.ServerError(w, r, err, "schedule removal failed", "schedule_id", sc.ScheduleID)
				return
			}
		}
	}
	t.Name, t.Icon, t.Color, t.Fields, t.GapHours = name, icon, req.Color, fields, req.GapHours.Value
	if err := h.stores.Trackers.Put(ctx, t); errors.Is(err, store.ErrNotFound) {
		httpx.WriteError(w, http.StatusNotFound, "not found")
		return
	} else if err != nil {
		httpx.ServerError(w, r, err, "update failed")
		return
	}
	h.writeDetail(w, r, http.StatusOK, t, now)
}

// Pause serves POST /v1/trackers/{trackerId}/pause.
func (h *Trackers) Pause(w http.ResponseWriter, r *http.Request) {
	h.setStatus(w, r, domain.TrackerPaused)
}

// Resume serves POST /v1/trackers/{trackerId}/resume.
func (h *Trackers) Resume(w http.ResponseWriter, r *http.Request) {
	h.setStatus(w, r, domain.TrackerActive)
}

// setStatus pauses or resumes; either is a no-op on a tracker already there.
// Pausing deletes the occurrences still to come; a repeat finds none left.
// Resuming a paused tracker generates its schedules again from now.
func (h *Trackers) setStatus(w http.ResponseWriter, r *http.Request, status domain.TrackerStatus) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	t, rc, ok := loadTracker(w, r, h.stores, r.PathValue("trackerId"))
	if !ok || !requireTeamRole(w, r, h.stores, c, t.TeamID, true) {
		return
	}
	ctx := r.Context()
	now := h.now().UTC()
	was := t.Status
	t, err := h.stores.Trackers.SetStatus(ctx, t.TrackerID, status, c.UserID, now)
	if errors.Is(err, store.ErrNotFound) {
		httpx.WriteError(w, http.StatusNotFound, "not found")
		return
	} else if err != nil {
		httpx.ServerError(w, r, err, "update failed")
		return
	}
	if status == domain.TrackerPaused {
		if _, err := h.stores.Entries.DeleteFutureOpenForTracker(ctx, t.TrackerID, now); err != nil {
			httpx.ServerError(w, r, err, "update failed")
			return
		}
	}
	if status == domain.TrackerActive && was == domain.TrackerPaused {
		// Its schedules generate again from now; nothing is back-filled across the pause.
		scs, err := h.stores.Schedules.ListLiveByTracker(ctx, t.TrackerID)
		if err != nil {
			httpx.ServerError(w, r, err, "schedule load failed")
			return
		}
		for _, sc := range scs {
			h.generateFromNow(ctx, sc, t, rc, now)
		}
	}
	h.writeDetail(w, r, http.StatusOK, t, now)
}
