package v1

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"sort"
	"strconv"
	"time"

	"github.com/google/uuid"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/logger"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
)

const (
	defaultAttentionLimit = 3
	maxAttentionLimit     = 50
	maxComingUpLimit      = 100
)

// Home serves the /v1 routes Home is built from: needs attention, coming up,
// the daily timeline, Quick log's waiting occurrences, Entry detail and
// Journal note, and the writes Quick log, Entry detail and the journal make.
type Home struct {
	stores *store.Stores
	now    func() time.Time
	newID  func() string
}

func NewHome(s *store.Stores) *Home { return &Home{stores: s, now: time.Now, newID: uuid.NewString} }

// trackerBadge is the TrackerBadge schema.
type trackerBadge struct {
	TrackerID string `json:"tracker_id"`
	Name      string `json:"name"`
	Icon      string `json:"icon"`
	Color     string `json:"color"`
}

func badgeOf(t domain.Tracker) trackerBadge {
	return trackerBadge{TrackerID: t.TrackerID, Name: t.Name, Icon: t.Icon, Color: t.Color}
}

// attentionItem is the AttentionItem schema.
type attentionItem struct {
	Tracker    trackerBadge     `json:"tracker"`
	Attention  trackerAttention `json:"attention"`
	FieldLabel string           `json:"field_label,omitempty"`
	Unit       string           `json:"unit,omitempty"`
}

// receiverEntry is the ReceiverEntry schema.
type receiverEntry struct {
	Tracker trackerBadge `json:"tracker"`
	Entry   entryView    `json:"entry"`
}

// journalNoteView is the JournalNote schema.
type journalNoteView struct {
	NoteID        string  `json:"note_id"`
	ReceiverID    string  `json:"receiver_id"`
	At            string  `json:"at"`
	Body          string  `json:"body"`
	AuthorName    string  `json:"author_name"`
	CreatedAt     string  `json:"created_at"`
	UpdatedByName string  `json:"updated_by_name,omitempty"`
	UpdatedAt     *string `json:"updated_at,omitempty"`
}

// timelineItem is the TimelineItem schema: an entry with its tracker, or a note.
type timelineItem struct {
	Kind    string           `json:"kind"`
	At      string           `json:"at"`
	Tracker *trackerBadge    `json:"tracker,omitempty"`
	Entry   *entryView       `json:"entry,omitempty"`
	Note    *journalNoteView `json:"note,omitempty"`
}

// dayTimeline is the DayTimeline schema.
type dayTimeline struct {
	Date  string         `json:"date"`
	Items []timelineItem `json:"items"`
}

// outOfRangeView is the OutOfRange schema.
type outOfRangeView struct {
	FieldID string     `json:"field_id"`
	Value   float64    `json:"value"`
	Range   valueRange `json:"range"`
}

// entryDetail is the EntryDetail schema.
type entryDetail struct {
	Entry           entryView        `json:"entry"`
	Tracker         trackerBadge     `json:"tracker"`
	Fields          []trackerField   `json:"fields"`
	Planned         bool             `json:"planned"`
	OccurrenceAt    *string          `json:"occurrence_at,omitempty"`
	UnrecordedAlert *bool            `json:"unrecorded_alert,omitempty"`
	SettledAt       *string          `json:"settled_at,omitempty"`
	UpdatedByName   string           `json:"updated_by_name,omitempty"`
	UpdatedAt       *string          `json:"updated_at,omitempty"`
	OutOfRange      []outOfRangeView `json:"out_of_range"`
}

// receiver loads the active receiver a /v1/receivers/{receiverId} read is
// about, checks the caller is on its team, and returns its time zone.
func (h *Home) receiver(w http.ResponseWriter, r *http.Request) (domain.Receiver, *time.Location, bool) {
	c := requireCaller(w, r)
	if c == nil {
		return domain.Receiver{}, nil, false
	}
	rc, ok := loadReceiver(w, r, h.stores, r.PathValue("receiverId"))
	if !ok || !requireTeamRole(w, r, h.stores, c, rc.TeamID, false) {
		return domain.Receiver{}, nil, false
	}
	loc, err := time.LoadLocation(rc.TimeZone)
	if err != nil {
		httpx.ServerError(w, r, err, "receiver time zone invalid", "receiver_id", rc.ReceiverID)
		return domain.Receiver{}, nil, false
	}
	return rc, loc, true
}

// queryLimit reads ?limit as an integer in [1, max], or def when absent; on a
// bad value it writes 400 and returns false.
func queryLimit(w http.ResponseWriter, r *http.Request, def, max int) (int, bool) {
	s := r.URL.Query().Get("limit")
	if s == "" {
		return def, true
	}
	n, err := strconv.Atoi(s)
	if err != nil || n < 1 || n > max {
		httpx.WriteError(w, http.StatusBadRequest, fmt.Sprintf("limit must be 1-%d", max))
		return 0, false
	}
	return n, true
}

// trackersOf reads the receiver's trackers, keyed by tracker_id, and the
// active ones in a stable order.
func (h *Home) trackersOf(ctx context.Context, receiverID string) (map[string]domain.Tracker, []domain.Tracker, error) {
	ts, err := h.stores.Trackers.ListByReceiver(ctx, receiverID)
	if err != nil {
		return nil, nil, err
	}
	sort.Slice(ts, func(i, j int) bool { return ts[i].TrackerID < ts[j].TrackerID })
	byID := make(map[string]domain.Tracker, len(ts))
	var active []domain.Tracker
	for _, t := range ts {
		byID[t.TrackerID] = t
		if t.Status == domain.TrackerActive {
			active = append(active, t)
		}
	}
	return byID, active, nil
}

// startOfDay is local midnight of the day d falls on in loc; the next day's is
// startOfDay(d).AddDate(0, 0, 1) normalized through time.Date, so a DST day is
// 23 or 25 hours long.
func startOfDay(d time.Time, loc *time.Location) time.Time {
	d = d.In(loc)
	return time.Date(d.Year(), d.Month(), d.Day(), 0, 0, 0, 0, loc)
}

func nextDay(start time.Time) time.Time {
	return time.Date(start.Year(), start.Month(), start.Day()+1, 0, 0, 0, 0, start.Location())
}

// Attention serves GET /v1/receivers/{receiverId}/attention: one item per
// active tracker, unrecorded care first, then out of range, then gap, capped
// at limit.
func (h *Home) Attention(w http.ResponseWriter, r *http.Request) {
	rc, _, ok := h.receiver(w, r)
	if !ok {
		return
	}
	limit, ok := queryLimit(w, r, defaultAttentionLimit, maxAttentionLimit)
	if !ok {
		return
	}
	ctx := r.Context()
	now := h.now().UTC()
	byID, active, err := h.trackersOf(ctx, rc.ReceiverID)
	if err != nil {
		httpx.ServerError(w, r, err, "tracker load failed")
		return
	}
	logged, err := recentLogged(ctx, h.stores, active)
	if err != nil {
		httpx.ServerError(w, r, err, "entry load failed")
		return
	}
	attention, err := receiverAttention(ctx, h.stores, rc.ReceiverID, active, logged, now)
	if err != nil {
		httpx.ServerError(w, r, err, "entry load failed")
		return
	}
	ranked := domain.RankAttention(attention, limit)
	out := make([]attentionItem, 0, len(ranked))
	for _, ta := range ranked {
		t := byID[ta.TrackerID]
		item := attentionItem{Tracker: badgeOf(t), Attention: attentionView(ta.Attention)}
		if ta.Kind == domain.AttentionOutOfRange {
			for _, f := range t.Fields {
				if f.FieldID == ta.FieldID {
					item.FieldLabel, item.Unit = f.Label, f.Unit
					break
				}
			}
		}
		out = append(out, item)
	}
	httpx.WriteJSON(w, http.StatusOK, out)
}

// ComingUp serves GET /v1/receivers/{receiverId}/coming-up: each active
// tracker's next scheduled entry still ahead, soonest first.
func (h *Home) ComingUp(w http.ResponseWriter, r *http.Request) {
	rc, _, ok := h.receiver(w, r)
	if !ok {
		return
	}
	limit, ok := queryLimit(w, r, 0, maxComingUpLimit)
	if !ok {
		return
	}
	ctx := r.Context()
	now := h.now().UTC()
	byID, active, err := h.trackersOf(ctx, rc.ReceiverID)
	if err != nil {
		httpx.ServerError(w, r, err, "tracker load failed")
		return
	}
	ids := make([]string, 0, len(active))
	for _, t := range active {
		ids = append(ids, t.TrackerID)
	}
	next, err := h.stores.Entries.NextOpenByTracker(ctx, ids, now)
	if err != nil {
		httpx.ServerError(w, r, err, "entry load failed")
		return
	}
	if limit > 0 && len(next) > limit {
		next = next[:limit]
	}
	h.writeReceiverEntries(w, r, byID, next, now)
}

// Waiting serves GET /v1/receivers/{receiverId}/waiting: what Quick log's
// picker leads with. Everything unrecorded from the last UnrecordedWindow,
// oldest first, then the rest of today's scheduled entries, soonest first;
// active trackers only.
func (h *Home) Waiting(w http.ResponseWriter, r *http.Request) {
	rc, loc, ok := h.receiver(w, r)
	if !ok {
		return
	}
	ctx := r.Context()
	now := h.now().UTC()
	byID, _, err := h.trackersOf(ctx, rc.ReceiverID)
	if err != nil {
		httpx.ServerError(w, r, err, "tracker load failed")
		return
	}
	since := now.Add(-domain.UnrecordedWindow)
	endOfToday := nextDay(startOfDay(now, loc))
	open, err := h.stores.Entries.OpenByReceiver(ctx, rc.ReceiverID, "", since, endOfToday.Add(-time.Nanosecond))
	if err != nil {
		httpx.ServerError(w, r, err, "entry load failed")
		return
	}
	// Paused trackers' past unrecorded entries are still open; they wait for
	// nobody. The window is open at its far end, as needs attention's is, so
	// an occurrence leaves both at the same instant.
	waiting := make([]domain.Entry, 0, len(open))
	for _, e := range open {
		t, ok := byID[e.TrackerID]
		if !ok {
			logMissingTracker(ctx, e)
			continue
		}
		if t.Status != domain.TrackerActive || e.OccurrenceAt == nil || !e.OccurrenceAt.After(since) {
			continue
		}
		waiting = append(waiting, e)
	}
	// Unrecorded (at or before now) oldest first, then scheduled soonest
	// first, is one ascending order by occurrence time.
	sort.SliceStable(waiting, func(i, j int) bool { return waiting[i].OccurrenceAt.Before(*waiting[j].OccurrenceAt) })
	h.writeReceiverEntries(w, r, byID, waiting, now)
}

// logMissingTracker logs an entry whose tracker is gone: corrupt data, left
// out of the read rather than failing it, so one bad row does not hide the
// rest.
func logMissingTracker(ctx context.Context, e domain.Entry) {
	logger.FromContext(ctx).Error("entry's tracker missing", "entry_id", e.EntryID, "tracker_id", e.TrackerID)
}

func (h *Home) writeReceiverEntries(w http.ResponseWriter, r *http.Request, byID map[string]domain.Tracker, entries []domain.Entry, now time.Time) {
	names, err := loadEntryNames(r.Context(), h.stores, entries)
	if err != nil {
		httpx.ServerError(w, r, err, "entry names load failed")
		return
	}
	out := make([]receiverEntry, 0, len(entries))
	for _, e := range entries {
		out = append(out, receiverEntry{Tracker: badgeOf(byID[e.TrackerID]), Entry: names.view(e, now)})
	}
	httpx.WriteJSON(w, http.StatusOK, out)
}

// Timeline serves GET /v1/receivers/{receiverId}/timeline?date=: one local day
// of entries and journal notes, oldest first. Occurrences still to come are
// left out; paused trackers' entries stay in.
func (h *Home) Timeline(w http.ResponseWriter, r *http.Request) {
	rc, loc, ok := h.receiver(w, r)
	if !ok {
		return
	}
	now := h.now().UTC()
	s := r.URL.Query().Get("date")
	day, err := time.ParseInLocation(time.DateOnly, s, loc)
	if err != nil || day.Format(time.DateOnly) != s {
		httpx.WriteError(w, http.StatusBadRequest, "date must be a date (YYYY-MM-DD)")
		return
	}
	if s > now.In(loc).Format(time.DateOnly) {
		httpx.WriteError(w, http.StatusBadRequest, "date must not be after today")
		return
	}
	start := startOfDay(day, loc)
	end := nextDay(start)

	ctx := r.Context()
	byID, _, err := h.trackersOf(ctx, rc.ReceiverID)
	if err != nil {
		httpx.ServerError(w, r, err, "tracker load failed")
		return
	}
	all, err := h.stores.Entries.ListByReceiverBetween(ctx, rc.ReceiverID, start, end)
	if err != nil {
		httpx.ServerError(w, r, err, "entry load failed")
		return
	}
	entries := make([]domain.Entry, 0, len(all))
	for _, e := range all {
		if e.DisplayState(now) == domain.EntryScheduled {
			continue // still to come: Coming up's, not the day's
		}
		if _, ok := byID[e.TrackerID]; !ok {
			logMissingTracker(ctx, e)
			continue
		}
		entries = append(entries, e)
	}
	notes, err := h.stores.JournalNotes.ListByReceiverBetween(ctx, rc.ReceiverID, start, end)
	if err != nil {
		httpx.ServerError(w, r, err, "journal note load failed")
		return
	}
	var noteUsers []string
	for _, n := range notes {
		noteUsers = append(noteUsers, n.Author, n.UpdatedBy)
	}
	names, err := loadEntryNames(ctx, h.stores, entries, noteUsers...)
	if err != nil {
		httpx.ServerError(w, r, err, "entry names load failed")
		return
	}

	type dated struct {
		at   time.Time
		item timelineItem
	}
	merged := make([]dated, 0, len(entries)+len(notes))
	for _, e := range entries {
		badge, v := badgeOf(byID[e.TrackerID]), names.view(e, now)
		merged = append(merged, dated{e.TimelineAt, timelineItem{Kind: "entry", At: apiTime(e.TimelineAt), Tracker: &badge, Entry: &v}})
	}
	for _, n := range notes {
		v := noteView(n, names.users)
		merged = append(merged, dated{n.At, timelineItem{Kind: "note", At: apiTime(n.At), Note: &v}})
	}
	// Both lists arrive oldest first; at an equal instant an entry comes
	// before a note.
	sort.SliceStable(merged, func(i, j int) bool { return merged[i].at.Before(merged[j].at) })
	out := dayTimeline{Date: s, Items: make([]timelineItem, 0, len(merged))}
	for _, d := range merged {
		out.Items = append(out.Items, d.item)
	}
	httpx.WriteJSON(w, http.StatusOK, out)
}

// noteView is n as the JournalNote schema, with users holding its author and
// last editor.
func noteView(n domain.JournalNote, users map[string]domain.User) journalNoteView {
	v := journalNoteView{
		NoteID: n.NoteID, ReceiverID: n.ReceiverID, At: apiTime(n.At), Body: n.Body,
		AuthorName: caregiverName(users, n.Author), CreatedAt: apiTime(n.CreatedAt),
	}
	if n.UpdatedBy != "" {
		v.UpdatedByName = caregiverName(users, n.UpdatedBy)
		v.UpdatedAt = apiTimePtr(n.UpdatedAt)
	}
	return v
}

// Entry serves GET /v1/entries/{entryId}: Entry detail, in whatever state the
// entry is in.
func (h *Home) Entry(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	ctx := r.Context()
	e, err := h.stores.Entries.Get(ctx, r.PathValue("entryId"))
	if errors.Is(err, store.ErrNotFound) {
		httpx.WriteError(w, http.StatusNotFound, "not found")
		return
	} else if err != nil {
		httpx.ServerError(w, r, err, "entry load failed")
		return
	}
	t, _, ok := loadTracker(w, r, h.stores, e.TrackerID)
	if !ok || !requireTeamRole(w, r, h.stores, c, t.TeamID, false) {
		return
	}
	d, err := h.entryDetail(ctx, e, t, h.now().UTC())
	if err != nil {
		httpx.ServerError(w, r, err, "entry names load failed")
		return
	}
	httpx.WriteJSON(w, http.StatusOK, d)
}

// entryDetail builds the EntryDetail of e, on tracker t, as it reads at now.
func (h *Home) entryDetail(ctx context.Context, e domain.Entry, t domain.Tracker, now time.Time) (entryDetail, error) {
	names, err := loadEntryNames(ctx, h.stores, []domain.Entry{e}, e.UpdatedBy)
	if err != nil {
		return entryDetail{}, err
	}
	d := entryDetail{
		Entry: names.view(e, now), Tracker: badgeOf(t), Fields: make([]trackerField, 0, len(t.Fields)),
		Planned: e.OccurrenceAt != nil, OutOfRange: []outOfRangeView{},
	}
	for _, f := range t.Fields {
		d.Fields = append(d.Fields, fieldView(f))
	}
	if d.Planned {
		alert := e.UnrecordedAlert
		d.OccurrenceAt, d.UnrecordedAlert = apiTimePtr(e.OccurrenceAt), &alert
	}
	switch e.State {
	case domain.EntryLogged:
		d.SettledAt = apiTimePtr(e.LoggedAt)
	case domain.EntrySkipped:
		d.SettledAt = apiTimePtr(e.SkippedAt)
	}
	if e.UpdatedBy != "" {
		d.UpdatedByName = caregiverName(names.users, e.UpdatedBy)
		d.UpdatedAt = apiTimePtr(e.UpdatedAt)
	}
	for _, o := range domain.OutOfRangeValues(t, e) {
		d.OutOfRange = append(d.OutOfRange, outOfRangeView{
			FieldID: o.FieldID, Value: o.Value, Range: valueRange{Low: o.Range.Low, High: o.Range.High},
		})
	}
	return d, nil
}

// JournalNote serves GET /v1/journal-notes/{noteId}.
func (h *Home) JournalNote(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	ctx := r.Context()
	n, err := h.stores.JournalNotes.Get(ctx, r.PathValue("noteId"))
	if errors.Is(err, store.ErrNotFound) {
		httpx.WriteError(w, http.StatusNotFound, "not found")
		return
	} else if err != nil {
		httpx.ServerError(w, r, err, "journal note load failed")
		return
	}
	rc, ok := loadReceiver(w, r, h.stores, n.ReceiverID)
	if !ok || !requireTeamRole(w, r, h.stores, c, rc.TeamID, false) {
		return
	}
	names, err := loadEntryNames(ctx, h.stores, nil, n.Author, n.UpdatedBy)
	if err != nil {
		httpx.ServerError(w, r, err, "caregiver load failed")
		return
	}
	httpx.WriteJSON(w, http.StatusOK, noteView(n, names.users))
}
