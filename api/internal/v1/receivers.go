package v1

import (
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"github.com/google/uuid"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/generate"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
)

// msgReceiverArchived is the ReceiverArchived 409.
const msgReceiverArchived = "this care receiver is archived; restore them to change anything"

// Receivers serves a team's care receivers (listing and adding them) and the
// routes about one: the Care receiver screen, editing, archiving and
// restoring, the care instructions and the emergency contacts.
type Receivers struct {
	stores *store.Stores
	now    func() time.Time
	newID  func() string
}

func NewReceivers(s *store.Stores) *Receivers {
	return &Receivers{stores: s, now: time.Now, newID: uuid.NewString}
}

// careReceiver is the CareReceiver schema.
type careReceiver struct {
	ReceiverID string `json:"receiver_id"`
	TeamID     string `json:"team_id"`
	Name       string `json:"name"`
	TimeZone   string `json:"time_zone"`
}

func careReceiverView(rc domain.Receiver) careReceiver {
	return careReceiver{ReceiverID: rc.ReceiverID, TeamID: rc.TeamID, Name: rc.Name, TimeZone: rc.TimeZone}
}

// ListByTeam serves GET /v1/teams/{teamId}/receivers: the active receivers by
// default, or with status=archived the archived ones, oldest first.
func (h *Receivers) ListByTeam(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	status := domain.ReceiverStatus(r.URL.Query().Get("status"))
	switch status {
	case "":
		status = domain.ReceiverActive
	case domain.ReceiverActive, domain.ReceiverArchived:
	default:
		httpx.WriteError(w, http.StatusBadRequest, "status must be active or archived")
		return
	}
	team, ok := loadTeam(w, r, h.stores, r.PathValue("teamId"))
	if !ok || !requireTeamRole(w, r, h.stores, c, team.TeamID, false) {
		return
	}
	rs, err := h.stores.Receivers.ListByTeam(r.Context(), team.TeamID, status)
	if err != nil {
		httpx.ServerError(w, r, err, "receiver load failed")
		return
	}
	out := make([]careReceiver, 0, len(rs))
	for _, rc := range rs {
		out = append(out, careReceiverView(rc))
	}
	httpx.WriteJSON(w, http.StatusOK, out)
}

// receiverBody is the NewCareReceiver and CareReceiverChanges schemas.
type receiverBody struct {
	Name     string `json:"name"`
	TimeZone string `json:"time_zone"`
}

// readReceiver decodes and validates a receiver's name and time zone, writing
// 400 and returning false when they are not valid.
func readReceiver(w http.ResponseWriter, r *http.Request) (name, tz string, ok bool) {
	var b receiverBody
	if err := json.NewDecoder(r.Body).Decode(&b); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid body")
		return "", "", false
	}
	name, err := domain.ValidateReceiverName(b.Name)
	if err != nil {
		httpx.WriteError(w, http.StatusBadRequest, err.Error())
		return "", "", false
	}
	tz, err = domain.ValidateTimeZone(b.TimeZone)
	if err != nil {
		httpx.WriteError(w, http.StatusBadRequest, err.Error())
		return "", "", false
	}
	return name, tz, true
}

// Create serves POST /v1/teams/{teamId}/receivers (Add receiver). Admins only.
func (h *Receivers) Create(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	team, ok := loadTeam(w, r, h.stores, r.PathValue("teamId"))
	if !ok || !requireTeamRole(w, r, h.stores, c, team.TeamID, true) {
		return
	}
	name, tz, ok := readReceiver(w, r)
	if !ok {
		return
	}
	rc := domain.Receiver{
		ReceiverID: h.newID(), TeamID: team.TeamID, Name: name, TimeZone: tz,
		Status: domain.ReceiverActive, CreatedBy: c.UserID, CreatedAt: h.now().UTC(),
	}
	if err := h.stores.Receivers.Create(r.Context(), rc); err != nil {
		httpx.ServerError(w, r, err, "create failed")
		return
	}
	httpx.WriteJSON(w, http.StatusCreated, careReceiverView(rc))
}

// careInstructionsView is the CareInstructions schema.
type careInstructionsView struct {
	Body          string `json:"body"`
	UpdatedByName string `json:"updated_by_name"`
	UpdatedAt     string `json:"updated_at"`
}

// emergencyContact is the EmergencyContact schema.
type emergencyContact struct {
	ContactID    string `json:"contact_id"`
	Name         string `json:"name"`
	Relationship string `json:"relationship"`
	Phone        string `json:"phone"`
}

// careReceiverDetail is the CareReceiverDetail schema.
type careReceiverDetail struct {
	ReceiverID        string                `json:"receiver_id"`
	TeamID            string                `json:"team_id"`
	TeamName          string                `json:"team_name"`
	Name              string                `json:"name"`
	TimeZone          string                `json:"time_zone"`
	Status            string                `json:"status"`
	ArchivedByName    string                `json:"archived_by_name,omitempty"`
	ArchivedAt        *string               `json:"archived_at,omitempty"`
	CareInstructions  *careInstructionsView `json:"care_instructions,omitempty"`
	EmergencyContacts []emergencyContact    `json:"emergency_contacts"`
}

// writeDetail writes the Care receiver screen's data for rc, on team, with
// status.
func (h *Receivers) writeDetail(w http.ResponseWriter, r *http.Request, status int, rc domain.Receiver, team domain.Team) {
	ctx := r.Context()
	ci, err := h.stores.CareInstructions.Get(ctx, rc.ReceiverID)
	if err != nil && !errors.Is(err, store.ErrNotFound) {
		httpx.ServerError(w, r, err, "care instructions load failed")
		return
	}
	var ids []string
	if ci.Body != "" {
		ids = append(ids, ci.UpdatedBy)
	}
	if rc.Status == domain.ReceiverArchived {
		ids = append(ids, rc.ArchivedBy)
	}
	users, err := h.stores.Users.BatchGet(ctx, ids)
	if err != nil {
		httpx.ServerError(w, r, err, "user load failed")
		return
	}
	out := careReceiverDetail{
		ReceiverID: rc.ReceiverID, TeamID: rc.TeamID, TeamName: team.Name, Name: rc.Name, TimeZone: rc.TimeZone,
		Status: string(rc.Status), EmergencyContacts: make([]emergencyContact, 0, len(ci.Contacts)),
	}
	if rc.Status == domain.ReceiverArchived {
		out.ArchivedByName = caregiverName(users, rc.ArchivedBy)
		out.ArchivedAt = apiTimePtr(rc.ArchivedAt)
	}
	if ci.Body != "" {
		v := careInstructionsView{Body: ci.Body, UpdatedByName: caregiverName(users, ci.UpdatedBy)}
		if ci.UpdatedAt != nil {
			v.UpdatedAt = apiTime(*ci.UpdatedAt)
		}
		out.CareInstructions = &v
	}
	for _, ct := range ci.Contacts {
		out.EmergencyContacts = append(out.EmergencyContacts, emergencyContact{
			ContactID: ct.ContactID, Name: ct.Name, Relationship: ct.Relationship, Phone: ct.Phone,
		})
	}
	httpx.WriteJSON(w, status, out)
}

// Get serves GET /v1/receivers/{receiverId} (Care receiver): any member, the
// receiver archived or not.
func (h *Receivers) Get(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	rc, team, ok := loadAnyReceiver(w, r, h.stores, r.PathValue("receiverId"))
	if !ok || !requireTeamRole(w, r, h.stores, c, rc.TeamID, false) {
		return
	}
	h.writeDetail(w, r, http.StatusOK, rc, team)
}

// Change serves PUT /v1/receivers/{receiverId} (Edit care receiver). Admins
// only. A new time zone keeps the receiver's routines at their wall-clock
// times: every scheduled entry still to come, and every assignment not yet
// begun, is re-resolved in it.
func (h *Receivers) Change(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	rc, _, ok := loadAnyReceiver(w, r, h.stores, r.PathValue("receiverId"))
	if !ok || !requireTeamRole(w, r, h.stores, c, rc.TeamID, true) || refuseArchived(w, rc) {
		return
	}
	name, tz, ok := readReceiver(w, r)
	if !ok {
		return
	}
	ctx := r.Context()
	rc, err := h.stores.Receivers.Change(ctx, rc.ReceiverID, name, tz)
	switch {
	case err == nil:
	case errors.Is(err, store.ErrReceiverArchived):
		httpx.WriteError(w, http.StatusConflict, msgReceiverArchived)
		return
	case errors.Is(err, store.ErrNotFound):
		httpx.WriteError(w, http.StatusNotFound, "not found")
		return
	default:
		httpx.ServerError(w, r, err, "update failed")
		return
	}
	// Run on every save, not only when the zone changed: it writes nothing
	// for entries already at their instant, and a save that failed here is
	// mended by saving again.
	if _, err := generate.Retime(ctx, h.stores, rc, h.now().UTC()); err != nil {
		httpx.ServerError(w, r, err, "re-resolving scheduled entries failed", "receiver_id", rc.ReceiverID)
		return
	}
	// Their assignments not yet begun move the same way, keeping their local
	// start and end.
	if _, err := generate.RetimeAssignments(ctx, h.stores, rc, h.now().UTC()); err != nil {
		httpx.ServerError(w, r, err, "re-resolving assignments failed", "receiver_id", rc.ReceiverID)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, careReceiverView(rc))
}

// Archive serves POST /v1/receivers/{receiverId}/archive. Admins only. Their
// still-waiting future scheduled entries are removed, as when a tracker is
// paused, and the generator makes no more; assignments are kept. Archiving
// one already archived is a 204, and removes anything still waiting again.
func (h *Receivers) Archive(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	rc, _, ok := loadAnyReceiver(w, r, h.stores, r.PathValue("receiverId"))
	if !ok || !requireTeamRole(w, r, h.stores, c, rc.TeamID, true) {
		return
	}
	ctx := r.Context()
	now := h.now().UTC()
	if _, err := h.stores.Receivers.SetStatus(ctx, rc.ReceiverID, domain.ReceiverArchived, c.UserID, now); errors.Is(err, store.ErrNotFound) {
		httpx.WriteError(w, http.StatusNotFound, "not found")
		return
	} else if err != nil {
		httpx.ServerError(w, r, err, "archive failed")
		return
	}
	if _, err := h.stores.Entries.DeleteFutureOpenForReceiver(ctx, rc.ReceiverID, now); err != nil {
		httpx.ServerError(w, r, err, "archive failed")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// Restore serves POST /v1/receivers/{receiverId}/restore. Admins only. Each
// tracker not paused generates its schedules again from now, and each live
// coverage schedule its assignments; nothing that came due while they were
// archived is made after the fact. Restoring one already
// active is a 204.
func (h *Receivers) Restore(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	rc, _, ok := loadAnyReceiver(w, r, h.stores, r.PathValue("receiverId"))
	if !ok || !requireTeamRole(w, r, h.stores, c, rc.TeamID, true) {
		return
	}
	ctx := r.Context()
	now := h.now().UTC()
	was := rc.Status
	rc, err := h.stores.Receivers.SetStatus(ctx, rc.ReceiverID, domain.ReceiverActive, c.UserID, now)
	if errors.Is(err, store.ErrNotFound) {
		httpx.WriteError(w, http.StatusNotFound, "not found")
		return
	} else if err != nil {
		httpx.ServerError(w, r, err, "restore failed")
		return
	}
	if was == domain.ReceiverArchived {
		trackers, err := h.stores.Trackers.ListByReceiver(ctx, rc.ReceiverID)
		if err != nil {
			httpx.ServerError(w, r, err, "tracker load failed")
			return
		}
		for _, t := range trackers {
			if t.Status == domain.TrackerPaused {
				continue
			}
			scs, err := h.stores.Schedules.ListLiveByTracker(ctx, t.TrackerID)
			if err != nil {
				httpx.ServerError(w, r, err, "schedule load failed")
				return
			}
			for _, sc := range scs {
				generateFromNow(ctx, h.stores, sc, t, rc, now)
			}
		}
		rules, err := h.stores.CoverageSchedules.ListLiveByReceiver(ctx, rc.ReceiverID)
		if err != nil {
			httpx.ServerError(w, r, err, "coverage schedule load failed")
			return
		}
		for _, cs := range rules {
			generateCoverageFromNow(ctx, h.stores, cs, rc, now)
		}
	}
	w.WriteHeader(http.StatusNoContent)
}

// refuseArchived writes 409 and returns true when the receiver, as read, is
// archived. The write that follows checks again in its own condition, so an
// archive landing in between is refused the same way.
func refuseArchived(w http.ResponseWriter, rc domain.Receiver) bool {
	if rc.Status != domain.ReceiverArchived {
		return false
	}
	httpx.WriteError(w, http.StatusConflict, msgReceiverArchived)
	return true
}

// writeCareErr maps a care-instructions write's error to its response, and
// reports whether there was one.
func writeCareErr(w http.ResponseWriter, r *http.Request, err error) bool {
	switch {
	case err == nil:
		return false
	case errors.Is(err, store.ErrReceiverArchived):
		httpx.WriteError(w, http.StatusConflict, msgReceiverArchived)
	case errors.Is(err, store.ErrNotFound):
		httpx.WriteError(w, http.StatusNotFound, "not found")
	default:
		httpx.ServerError(w, r, err, "update failed")
	}
	return true
}

// ChangeCareInstructions serves PUT /v1/receivers/{receiverId}/care-instructions
// (Edit care instructions). Admins only. It records who changed them and when;
// an empty body clears them, and the stamp with them.
func (h *Receivers) ChangeCareInstructions(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	rc, team, ok := loadAnyReceiver(w, r, h.stores, r.PathValue("receiverId"))
	if !ok || !requireTeamRole(w, r, h.stores, c, rc.TeamID, true) || refuseArchived(w, rc) {
		return
	}
	var req struct {
		Body *string `json:"body"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid body")
		return
	}
	if req.Body == nil {
		httpx.WriteError(w, http.StatusBadRequest, "body is required")
		return
	}
	body, err := domain.ValidateCareInstructions(*req.Body)
	if err != nil {
		httpx.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	if writeCareErr(w, r, h.stores.SetCareInstructionsBody(r.Context(), rc, body, c.UserID, h.now().UTC())) {
		return
	}
	h.writeDetail(w, r, http.StatusOK, rc, team)
}

// ChangeEmergencyContacts serves PUT /v1/receivers/{receiverId}/emergency-contacts.
// Admins only. The list sent replaces the one there, in its order; a contact
// sent with its contact_id keeps it, one without is new, one left out is
// removed. Who last changed the care instructions is left as it was.
func (h *Receivers) ChangeEmergencyContacts(w http.ResponseWriter, r *http.Request) {
	c := requireCaller(w, r)
	if c == nil {
		return
	}
	rc, team, ok := loadAnyReceiver(w, r, h.stores, r.PathValue("receiverId"))
	if !ok || !requireTeamRole(w, r, h.stores, c, rc.TeamID, true) || refuseArchived(w, rc) {
		return
	}
	var req struct {
		Contacts *[]struct {
			ContactID    string `json:"contact_id"`
			Name         string `json:"name"`
			Relationship string `json:"relationship"`
			Phone        string `json:"phone"`
		} `json:"contacts"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid body")
		return
	}
	if req.Contacts == nil {
		httpx.WriteError(w, http.StatusBadRequest, "contacts is required")
		return
	}
	ctx := r.Context()
	ci, err := h.stores.CareInstructions.Get(ctx, rc.ReceiverID)
	if err != nil && !errors.Is(err, store.ErrNotFound) {
		httpx.ServerError(w, r, err, "care instructions load failed")
		return
	}
	in := make([]domain.ContactWrite, 0, len(*req.Contacts))
	for _, ct := range *req.Contacts {
		in = append(in, domain.ContactWrite{ContactID: ct.ContactID, Name: ct.Name, Relationship: ct.Relationship, Phone: ct.Phone})
	}
	contacts, err := domain.ResolveContacts(in, ci.Contacts, h.newID)
	if err != nil {
		httpx.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	if writeCareErr(w, r, h.stores.SetEmergencyContacts(ctx, rc, contacts)) {
		return
	}
	h.writeDetail(w, r, http.StatusOK, rc, team)
}
