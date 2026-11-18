package v1

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"github.com/google/uuid"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/logger"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/generate"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
)

// msgAssignmentEnded is the AssignmentEnded 409.
const msgAssignmentEnded = "this assignment has already ended; it stays as it is"

// msgNotOnTeam is the 400 for a user_id that is not a caregiver on the team.
const msgNotOnTeam = "user_id must be a caregiver on this care team"

// Coverage serves a care receiver's roster: who is on duty, the assignments
// ahead, and the coverage schedules behind them (PRD, Assignment and Coverage
// schedule). Any member reads it; admins change it. An archived receiver's
// roster is read-only, and a closed team's is unreachable.
type Coverage struct {
	stores *store.Stores
	now    func() time.Time
	newID  func() string
}

func NewCoverage(s *store.Stores) *Coverage {
	return &Coverage{stores: s, now: time.Now, newID: uuid.NewString}
}

// assignmentView is the Assignment schema.
type assignmentView struct {
	AssignmentID       string `json:"assignment_id"`
	ReceiverID         string `json:"receiver_id"`
	UserID             string `json:"user_id"`
	CaregiverName      string `json:"caregiver_name"`
	StartsLocal        string `json:"starts_local"`
	EndsLocal          string `json:"ends_local"`
	StartsAt           string `json:"starts_at"`
	EndsAt             string `json:"ends_at"`
	CoverageScheduleID string `json:"coverage_schedule_id,omitempty"`
}

// coverageScheduleView is the CoverageSchedule schema.
type coverageScheduleView struct {
	CoverageScheduleID string     `json:"coverage_schedule_id"`
	ReceiverID         string     `json:"receiver_id"`
	UserID             string     `json:"user_id"`
	CaregiverName      string     `json:"caregiver_name"`
	Rule               recurrence `json:"rule"`
	StartTime          string     `json:"start_time"`
	EndTime            string     `json:"end_time"`
	StartsOn           string     `json:"starts_on"`
	EndsOn             string     `json:"ends_on,omitempty"`
}

// rosterNames names whoever is on the team now, and anyone else — someone who
// has left, or closed their account — "a former caregiver".
type rosterNames func(userID string) string

func (h *Coverage) names(ctx context.Context, teamID string) (rosterNames, error) {
	members, err := h.stores.Memberships.ListByTeam(ctx, teamID)
	if err != nil {
		return nil, err
	}
	on := make(map[string]bool, len(members))
	ids := make([]string, 0, len(members))
	for _, m := range members {
		on[m.UserID] = true
		ids = append(ids, m.UserID)
	}
	users, err := h.stores.Users.BatchGet(ctx, ids)
	if err != nil {
		return nil, err
	}
	return func(id string) string {
		if !on[id] {
			return formerCaregiver
		}
		return caregiverName(users, id)
	}, nil
}

func assignmentOut(a domain.Assignment, name rosterNames) assignmentView {
	return assignmentView{
		AssignmentID: a.AssignmentID, ReceiverID: a.ReceiverID, UserID: a.UserID, CaregiverName: name(a.UserID),
		StartsLocal: a.StartsLocal, EndsLocal: a.EndsLocal, StartsAt: apiTime(a.StartsAt), EndsAt: apiTime(a.EndsAt),
		CoverageScheduleID: a.RuleID(),
	}
}

func coverageScheduleOut(cs domain.CoverageSchedule, name rosterNames) coverageScheduleView {
	v := coverageScheduleView{
		CoverageScheduleID: cs.CoverageScheduleID, ReceiverID: cs.ReceiverID, UserID: cs.UserID, CaregiverName: name(cs.UserID),
		Rule:      recurrence{Freq: cs.Rule.Freq, Interval: cs.Rule.Interval, ByDay: cs.Rule.ByDay},
		StartTime: cs.StartTime, EndTime: cs.EndTime, StartsOn: cs.StartsOn, EndsOn: cs.EndsOn,
	}
	if v.Rule.ByDay == nil {
		v.Rule.ByDay = []string{}
	}
	return v
}

// writeAssignments writes the assignments, named, with status.
func (h *Coverage) writeAssignments(w http.ResponseWriter, r *http.Request, teamID string, as []domain.Assignment) {
	name, err := h.names(r.Context(), teamID)
	if err != nil {
		httpx.ServerError(w, r, err, "caregiver load failed")
		return
	}
	out := make([]assignmentView, 0, len(as))
	for _, a := range as {
		out = append(out, assignmentOut(a, name))
	}
	httpx.WriteJSON(w, http.StatusOK, out)
}

// readReceiverRoster loads a receiver's roster for any member: the receiver,
// archived or not, on an open team.
func (h *Coverage) readReceiverRoster(w http.ResponseWriter, r *http.Request) (domain.Receiver, bool) {
	c := requireCaller(w, r)
	if c == nil {
		return domain.Receiver{}, false
	}
	rc, _, ok := loadAnyReceiver(w, r, h.stores, r.PathValue("receiverId"))
	if !ok || !requireTeamRole(w, r, h.stores, c, rc.TeamID, false) {
		return domain.Receiver{}, false
	}
	return rc, true
}

// OnDuty serves GET /v1/receivers/{receiverId}/on-duty: every assignment
// covering this moment, soonest start first. Empty when nobody is assigned.
func (h *Coverage) OnDuty(w http.ResponseWriter, r *http.Request) {
	rc, ok := h.readReceiverRoster(w, r)
	if !ok {
		return
	}
	now := h.now().UTC()
	as, err := h.stores.Assignments.NotEndedByReceiver(r.Context(), rc.ReceiverID, now)
	if err != nil {
		httpx.ServerError(w, r, err, "assignment load failed")
		return
	}
	onDuty := make([]domain.Assignment, 0, len(as))
	for _, a := range as {
		if !a.StartsAt.After(now) {
			onDuty = append(onDuty, a)
		}
	}
	h.writeAssignments(w, r, rc.TeamID, onDuty)
}

// Assignments serves GET /v1/receivers/{receiverId}/assignments: every
// assignment that has not yet ended, under way or ahead, soonest first.
func (h *Coverage) Assignments(w http.ResponseWriter, r *http.Request) {
	rc, ok := h.readReceiverRoster(w, r)
	if !ok {
		return
	}
	as, err := h.stores.Assignments.NotEndedByReceiver(r.Context(), rc.ReceiverID, h.now().UTC())
	if err != nil {
		httpx.ServerError(w, r, err, "assignment load failed")
		return
	}
	h.writeAssignments(w, r, rc.TeamID, as)
}

// writeReceiverRoster loads a receiver's roster for an admin to change: the
// receiver on an open team, refused with 409 while archived.
func (h *Coverage) writeReceiverRoster(w http.ResponseWriter, r *http.Request, c *caller, receiverID string) (domain.Receiver, bool) {
	rc, _, ok := loadAnyReceiver(w, r, h.stores, receiverID)
	if !ok || !requireTeamRole(w, r, h.stores, c, rc.TeamID, true) || refuseArchived(w, rc) {
		return domain.Receiver{}, false
	}
	return rc, true
}

// requireOnTeam writes 400 and returns false unless userID is a caregiver on
// the team now.
func (h *Coverage) requireOnTeam(w http.ResponseWriter, r *http.Request, userID, teamID string) bool {
	if userID == "" {
		httpx.WriteError(w, http.StatusBadRequest, msgNotOnTeam)
		return false
	}
	_, err := h.stores.Memberships.Get(r.Context(), userID, teamID)
	if errors.Is(err, store.ErrNotFound) {
		httpx.WriteError(w, http.StatusBadRequest, msgNotOnTeam)
		return false
	} else if err != nil {
		httpx.ServerError(w, r, err, "membership load failed")
		return false
	}
	return true
}

// receiverZone loads the receiver's time zone, writing 500 when it is not one.
func receiverZone(w http.ResponseWriter, r *http.Request, rc domain.Receiver) (*time.Location, bool) {
	loc, err := time.LoadLocation(rc.TimeZone)
	if err != nil {
		httpx.ServerError(w, r, err, "receiver time zone invalid", "receiver_id", rc.ReceiverID)
		return nil, false
	}
	return loc, true
}

// assignmentBody is the AssignmentWrite schema.
type assignmentBody struct {
	UserID      string `json:"user_id"`
	StartsLocal string `json:"starts_local"`
	EndsLocal   string `json:"ends_local"`
}

// readAssignment decodes and validates an assignment's Save onto a: who
// covers, and when, local to the receiver. It must end after it starts and
// after now, and name a caregiver on the team.
func (h *Coverage) readAssignment(w http.ResponseWriter, r *http.Request, rc domain.Receiver, a domain.Assignment, now time.Time) (domain.Assignment, bool) {
	var b assignmentBody
	if err := json.NewDecoder(r.Body).Decode(&b); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid body")
		return a, false
	}
	if _, err := domain.ParseLocalDateTime("starts_local", b.StartsLocal); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, err.Error())
		return a, false
	}
	if _, err := domain.ParseLocalDateTime("ends_local", b.EndsLocal); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, err.Error())
		return a, false
	}
	loc, ok := receiverZone(w, r, rc)
	if !ok {
		return a, false
	}
	starts, _ := generate.ResolveLocal(b.StartsLocal, loc)
	ends, _ := generate.ResolveLocal(b.EndsLocal, loc)
	if err := domain.ValidateAssignmentSpan(starts, ends, now); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, err.Error())
		return a, false
	}
	if !h.requireOnTeam(w, r, b.UserID, rc.TeamID) {
		return a, false
	}
	a.UserID, a.StartsLocal, a.EndsLocal, a.StartsAt, a.EndsAt = b.UserID, b.StartsLocal, b.EndsLocal, starts, ends
	return a, true
}

// writeAssignment writes one assignment, named, with status.
func (h *Coverage) writeAssignment(w http.ResponseWriter, r *http.Request, status int, a domain.Assignment) {
	name, err := h.names(r.Context(), a.TeamID)
	if err != nil {
		httpx.ServerError(w, r, err, "caregiver load failed")
		return
	}
	httpx.WriteJSON(w, status, assignmentOut(a, name))
}

// AddAssignment serves POST /v1/receivers/{receiverId}/assignments (An
// assignment — Save, for a new one). Admins only. It belongs to no rule.
func (h *Coverage) AddAssignment(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	rc, ok := h.writeReceiverRoster(w, r, c, r.PathValue("receiverId"))
	if !ok {
		return
	}
	now := h.now().UTC()
	a, ok := h.readAssignment(w, r, rc, domain.Assignment{
		AssignmentID: h.newID(), ReceiverID: rc.ReceiverID, TeamID: rc.TeamID,
		Status: domain.AssignmentActive, CreatedBy: c.UserID, CreatedAt: now,
	}, now)
	if !ok {
		return
	}
	if err := h.stores.Assignments.Create(r.Context(), a); err != nil {
		httpx.ServerError(w, r, err, "create failed")
		return
	}
	h.writeAssignment(w, r, http.StatusCreated, a)
}

// loadAssignmentToChange loads an assignment an admin is changing or
// removing: 404 when it is unknown or removed, or its team is closed; 409
// while its receiver is archived, or once it has ended.
func (h *Coverage) loadAssignmentToChange(w http.ResponseWriter, r *http.Request, c *caller, now time.Time) (domain.Assignment, domain.Receiver, bool) {
	a, err := h.stores.Assignments.Get(r.Context(), r.PathValue("assignmentId"))
	if errors.Is(err, store.ErrNotFound) || (err == nil && a.Status != domain.AssignmentActive) {
		httpx.WriteError(w, http.StatusNotFound, "not found")
		return a, domain.Receiver{}, false
	} else if err != nil {
		httpx.ServerError(w, r, err, "assignment load failed")
		return a, domain.Receiver{}, false
	}
	rc, ok := h.writeReceiverRoster(w, r, c, a.ReceiverID)
	if !ok {
		return a, rc, false
	}
	if !a.EndsAt.After(now) {
		httpx.WriteError(w, http.StatusConflict, msgAssignmentEnded)
		return a, rc, false
	}
	return a, rc, true
}

// writeAssignmentErr maps a hand change's error to its response, and reports
// whether there was one.
func writeAssignmentErr(w http.ResponseWriter, r *http.Request, err error, msg string) bool {
	switch {
	case err == nil:
		return false
	case errors.Is(err, store.ErrAssignmentEnded):
		httpx.WriteError(w, http.StatusConflict, msgAssignmentEnded)
	case errors.Is(err, store.ErrNotFound):
		httpx.WriteError(w, http.StatusNotFound, "not found")
	default:
		httpx.ServerError(w, r, err, msg)
	}
	return true
}

// ChangeAssignment serves PUT /v1/assignments/{assignmentId} (An assignment —
// Save, or Hand to someone else). Admins only. It changes this one assignment
// and nothing else; one a rule made belongs to no rule afterward.
func (h *Coverage) ChangeAssignment(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	now := h.now().UTC()
	a, rc, ok := h.loadAssignmentToChange(w, r, c, now)
	if !ok {
		return
	}
	if a, ok = h.readAssignment(w, r, rc, a, now); !ok {
		return
	}
	stored, err := h.stores.Assignments.Change(r.Context(), a, c.UserID, now)
	if writeAssignmentErr(w, r, err, "update failed") {
		return
	}
	h.writeAssignment(w, r, http.StatusOK, stored)
}

// RemoveAssignment serves DELETE /v1/assignments/{assignmentId} (An
// assignment — Remove). Admins only. The rule that made it is left as it was,
// and does not make it again.
func (h *Coverage) RemoveAssignment(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	now := h.now().UTC()
	a, _, ok := h.loadAssignmentToChange(w, r, c, now)
	if !ok {
		return
	}
	if writeAssignmentErr(w, r, h.stores.Assignments.Remove(r.Context(), a, c.UserID, now), "remove failed") {
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// CoverageSchedules serves GET /v1/receivers/{receiverId}/coverage-schedules:
// the rules not removed, ended or not, oldest first.
func (h *Coverage) CoverageSchedules(w http.ResponseWriter, r *http.Request) {
	rc, ok := h.readReceiverRoster(w, r)
	if !ok {
		return
	}
	ctx := r.Context()
	rules, err := h.stores.CoverageSchedules.ListLiveByReceiver(ctx, rc.ReceiverID)
	if err != nil {
		httpx.ServerError(w, r, err, "coverage schedule load failed")
		return
	}
	name, err := h.names(ctx, rc.TeamID)
	if err != nil {
		httpx.ServerError(w, r, err, "caregiver load failed")
		return
	}
	out := make([]coverageScheduleView, 0, len(rules))
	for _, cs := range rules {
		out = append(out, coverageScheduleOut(cs, name))
	}
	httpx.WriteJSON(w, http.StatusOK, out)
}

// coverageScheduleBody is the CoverageScheduleWrite schema.
type coverageScheduleBody struct {
	UserID    string      `json:"user_id"`
	Rule      *recurrence `json:"rule"`
	StartTime string      `json:"start_time"`
	EndTime   string      `json:"end_time"`
	EndsOn    string      `json:"ends_on"`
}

// readCoverageSchedule decodes and validates a coverage schedule's Save, and
// returns the receiver's today. storedEndsOn is a changed rule's ends_on ("" for
// a new one): sent back unchanged, it is not held to "not before today".
func (h *Coverage) readCoverageSchedule(w http.ResponseWriter, r *http.Request, rc domain.Receiver, now time.Time, storedEndsOn string) (domain.CoverageScheduleWrite, string, bool) {
	var b coverageScheduleBody
	if err := json.NewDecoder(r.Body).Decode(&b); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid body")
		return domain.CoverageScheduleWrite{}, "", false
	}
	if b.Rule == nil {
		httpx.WriteError(w, http.StatusBadRequest, "user_id, rule, start_time and end_time are required")
		return domain.CoverageScheduleWrite{}, "", false
	}
	loc, ok := receiverZone(w, r, rc)
	if !ok {
		return domain.CoverageScheduleWrite{}, "", false
	}
	today := now.In(loc).Format(time.DateOnly)
	cw, err := domain.ValidateCoverageScheduleWrite(domain.CoverageScheduleWrite{
		UserID: b.UserID, Rule: domain.Rule{Freq: b.Rule.Freq, Interval: b.Rule.Interval, ByDay: b.Rule.ByDay},
		StartTime: b.StartTime, EndTime: b.EndTime, EndsOn: b.EndsOn,
	}, today, storedEndsOn)
	if err != nil {
		httpx.WriteError(w, http.StatusBadRequest, err.Error())
		return cw, "", false
	}
	if !h.requireOnTeam(w, r, cw.UserID, rc.TeamID) {
		return cw, "", false
	}
	return cw, today, true
}

// generateCoverage makes the rule's assignments from now on. It runs after
// the rule is saved, so a failure is logged rather than failing the request,
// and the daily job fills them in on its next run.
func (h *Coverage) generateCoverage(ctx context.Context, cs domain.CoverageSchedule, rc domain.Receiver, now time.Time) {
	generateCoverageFromNow(ctx, h.stores, cs, rc, now)
}

func generateCoverageFromNow(ctx context.Context, s *store.Stores, cs domain.CoverageSchedule, rc domain.Receiver, now time.Time) {
	if _, err := generate.GenerateCoverage(ctx, s, cs, rc, now, now); err != nil {
		logger.FromContext(ctx).Error("coverage generation failed; the daily job will fill it in",
			"err", err.Error(), "coverage_schedule_id", cs.CoverageScheduleID, "receiver_id", cs.ReceiverID)
	}
}

// writeCoverageSchedule writes one rule, named, with status.
func (h *Coverage) writeCoverageSchedule(w http.ResponseWriter, r *http.Request, status int, cs domain.CoverageSchedule) {
	name, err := h.names(r.Context(), cs.TeamID)
	if err != nil {
		httpx.ServerError(w, r, err, "caregiver load failed")
		return
	}
	httpx.WriteJSON(w, status, coverageScheduleOut(cs, name))
}

// AddCoverageSchedule serves POST /v1/receivers/{receiverId}/coverage-schedules
// (A coverage schedule — Save, for a new one). Admins only. It starts today in
// the receiver's zone and makes its assignments ahead, from a slot already
// under way.
func (h *Coverage) AddCoverageSchedule(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	rc, ok := h.writeReceiverRoster(w, r, c, r.PathValue("receiverId"))
	if !ok {
		return
	}
	now := h.now().UTC()
	cw, today, ok := h.readCoverageSchedule(w, r, rc, now, "")
	if !ok {
		return
	}
	cs := domain.CoverageSchedule{
		CoverageScheduleID: h.newID(), ReceiverID: rc.ReceiverID, TeamID: rc.TeamID, UserID: cw.UserID,
		Rule: cw.Rule, StartTime: cw.StartTime, EndTime: cw.EndTime, StartsOn: today, EndsOn: cw.EndsOn,
		CreatedBy: c.UserID, CreatedAt: now, UpdatedAt: now,
	}
	ctx := r.Context()
	if err := h.stores.CoverageSchedules.Create(ctx, cs); err != nil {
		httpx.ServerError(w, r, err, "create failed")
		return
	}
	h.generateCoverage(ctx, cs, rc, now)
	h.writeCoverageSchedule(w, r, http.StatusCreated, cs)
}

// loadCoverageScheduleToChange loads a rule an admin is changing or removing:
// 404 when it is unknown (or removed, unless removedOK), or its team is
// closed; 409 while its receiver is archived.
func (h *Coverage) loadCoverageScheduleToChange(w http.ResponseWriter, r *http.Request, c *caller, removedOK bool) (domain.CoverageSchedule, domain.Receiver, bool) {
	cs, err := h.stores.CoverageSchedules.Get(r.Context(), r.PathValue("coverageScheduleId"))
	if errors.Is(err, store.ErrNotFound) || (err == nil && cs.RemovedAt != nil && !removedOK) {
		httpx.WriteError(w, http.StatusNotFound, "not found")
		return cs, domain.Receiver{}, false
	} else if err != nil {
		httpx.ServerError(w, r, err, "coverage schedule load failed")
		return cs, domain.Receiver{}, false
	}
	rc, ok := h.writeReceiverRoster(w, r, c, cs.ReceiverID)
	return cs, rc, ok
}

// ChangeCoverageSchedule serves PUT /v1/coverage-schedules/{coverageScheduleId}
// (A coverage schedule — Save, for an existing one). Admins only. The
// assignments it made that have not begun are redrawn from the new rule;
// any changed by hand, and any already under way or past, stay as they are.
func (h *Coverage) ChangeCoverageSchedule(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	cs, rc, ok := h.loadCoverageScheduleToChange(w, r, c, false)
	if !ok {
		return
	}
	now := h.now().UTC()
	cw, _, ok := h.readCoverageSchedule(w, r, rc, now, cs.EndsOn)
	if !ok {
		return
	}
	cs.UserID, cs.Rule, cs.StartTime, cs.EndTime, cs.EndsOn, cs.UpdatedAt = cw.UserID, cw.Rule, cw.StartTime, cw.EndTime, cw.EndsOn, now
	ctx := r.Context()
	stored, err := h.stores.CoverageSchedules.Update(ctx, cs)
	if errors.Is(err, store.ErrNotFound) {
		httpx.WriteError(w, http.StatusNotFound, "not found")
		return
	} else if err != nil {
		httpx.ServerError(w, r, err, "update failed")
		return
	}
	if _, err := h.stores.Assignments.DeleteFutureForSchedule(ctx, stored.CoverageScheduleID, now); err != nil {
		httpx.ServerError(w, r, err, "update failed")
		return
	}
	h.generateCoverage(ctx, stored, rc, now)
	h.writeCoverageSchedule(w, r, http.StatusOK, stored)
}

// RemoveCoverageSchedule serves DELETE /v1/coverage-schedules/{coverageScheduleId}
// (Remove this coverage schedule? — Remove). Admins only. The rule and the
// assignments it made that have not begun go; past ones, one under way, and
// any changed by hand stay. The row stays, marked removed. Repeating it is
// safe, and answers 204.
func (h *Coverage) RemoveCoverageSchedule(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	cs, _, ok := h.loadCoverageScheduleToChange(w, r, c, true)
	if !ok {
		return
	}
	ctx := r.Context()
	now := h.now().UTC()
	if err := h.stores.CoverageSchedules.MarkRemoved(ctx, cs.CoverageScheduleID, now); err != nil && !errors.Is(err, store.ErrNotFound) {
		httpx.ServerError(w, r, err, "remove failed")
		return
	}
	if _, err := h.stores.Assignments.DeleteFutureForSchedule(ctx, cs.CoverageScheduleID, now); err != nil {
		httpx.ServerError(w, r, err, "remove failed")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
