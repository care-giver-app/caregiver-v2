package features_test

import (
	"context"
	"fmt"
	"net/http"
	"sort"
	"strings"
	"time"

	"github.com/cucumber/godog"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
)

// teamWorld is what a scenario last saw of the Team area: a care team's
// roster and pending invitations, a care receiver's screen, and the invite
// code each address was given when an admin invited it.
type teamWorld struct {
	detail   *teamDetailView
	pending  []teamInvitationView
	receiver *careReceiverView
	invited  map[string]string // email → the code its invitation was created with
}

func (w *world) registerTeam(sc *godog.ScenarioContext) {
	sc.Step(`^"([^"]*)" has joined "([^"]*)" as an? (admin|caregiver)$`, w.hasJoinedAs)

	sc.Step(`^"([^"]*)" opens the care team "([^"]*)"$`, w.opensTeam)
	sc.Step(`^the care team's caregivers are:$`, w.caregiversAre)

	sc.Step(`^"([^"]*)" makes "([^"]*)" an? (admin|caregiver) on "([^"]*)"$`, w.makesRole)
	sc.Step(`^"([^"]*)" removes "([^"]*)" from "([^"]*)"$`, w.removesFrom)
	sc.Step(`^"([^"]*)" leaves "([^"]*)"$`, w.leaves)
	sc.Step(`^"([^"]*)" closes "([^"]*)"$`, w.closes)

	sc.Step(`^"([^"]*)" invites "([^"]*)" to "([^"]*)"$`, w.invitesThroughApp)
	sc.Step(`^"([^"]*)" opens the pending invitations of "([^"]*)"$`, w.opensPending)
	sc.Step(`^the invitations pending are for `+quoted+`, each with the invite code it was created with$`, w.pendingAreFor)
	sc.Step(`^no invitations are pending$`, w.noInvitationsPending)

	sc.Step(`^"([^"]*)" (?:turns|has turned) (on|off) (reminders|out-of-range alerts|gap alerts|unrecorded-care alerts) for "([^"]*)"$`, w.turnsNotification)
	sc.Step(`^"([^"]*)" (gets|does not get) (reminders|out-of-range alerts|gap alerts|unrecorded-care alerts) from "([^"]*)"$`, w.getsNotification)

	sc.Step(`^"([^"]*)" adds the care receiver "([^"]*)" to "([^"]*)", keeping time in "([^"]*)"$`, w.addsReceiver)
	sc.Step(`^"([^"]*)" opens the archived care receivers of "([^"]*)"$`, w.opensArchivedReceivers)
	sc.Step(`^no care receivers are listed$`, w.noReceiversListed)
	sc.Step(`^"([^"]*)" renames the care receiver "([^"]*)" to "([^"]*)"$`, w.renamesReceiver)
	sc.Step(`^"([^"]*)" moves the care receiver "([^"]*)" to the time zone "([^"]*)"$`, w.movesReceiver)
	sc.Step(`^"([^"]*)" (archives|restores) the care receiver "([^"]*)"$`, w.archivesReceiver)

	sc.Step(`^"([^"]*)" opens the care receiver "([^"]*)"$`, w.opensReceiver)
	sc.Step(`^the care receiver is "([^"]*)" of "([^"]*)", keeping time in "([^"]*)"$`, w.receiverIs)
	sc.Step(`^the care receiver reads as (archived|active)$`, w.receiverReadsAs)
	sc.Step(`^the care receiver has no care instructions yet$`, w.noInstructionsYet)
	sc.Step(`^the care instructions read "([^"]*)", last changed by "([^"]*)" just now$`, w.instructionsRead)
	sc.Step(`^the care receiver has no emergency contacts yet$`, w.noContactsYet)
	sc.Step(`^the emergency contacts are, in order:$`, w.contactsAre)

	sc.Step(`^"([^"]*)" writes the care instructions for "([^"]*)": "([^"]*)"$`, w.writesInstructions)
	sc.Step(`^"([^"]*)" clears the care instructions for "([^"]*)"$`, w.clearsInstructions)
	sc.Step(`^"([^"]*)" sets the emergency contacts of "([^"]*)" to:$`, w.setsContacts)

	sc.Step(`^the next "([^"]*)" coming up is due at (\d\d:\d\d) in "([^"]*)"$`, w.nextComingUpAt)
}

// ---- API shapes -------------------------------------------------------------

type teamMemberView struct {
	UserID string `json:"user_id"`
	Name   string `json:"name"`
	Role   string `json:"role"`
}

type teamDetailView struct {
	TeamID  string           `json:"team_id"`
	Name    string           `json:"name"`
	MyRole  string           `json:"my_role"`
	Members []teamMemberView `json:"members"`
}

type teamInvitationView struct {
	Code          string `json:"code"`
	Email         string `json:"email"`
	InvitedByName string `json:"invited_by_name"`
}

type notificationChoicesView map[string]bool

// notificationKinds maps how a feature names a kind of notification to the
// field the API holds it in.
var notificationKinds = map[string]string{
	"reminders":              "reminders",
	"out-of-range alerts":    "range_alerts",
	"gap alerts":             "gap_alerts",
	"unrecorded-care alerts": "unrecorded_alerts",
}

type careInstructionsView struct {
	Body          string `json:"body"`
	UpdatedByName string `json:"updated_by_name"`
	UpdatedAt     string `json:"updated_at"`
}

type emergencyContactView struct {
	ContactID    string `json:"contact_id"`
	Name         string `json:"name"`
	Relationship string `json:"relationship"`
	Phone        string `json:"phone"`
}

type careReceiverView struct {
	ReceiverID        string                 `json:"receiver_id"`
	TeamID            string                 `json:"team_id"`
	TeamName          string                 `json:"team_name"`
	Name              string                 `json:"name"`
	TimeZone          string                 `json:"time_zone"`
	Status            string                 `json:"status"`
	CareInstructions  *careInstructionsView  `json:"care_instructions"`
	EmergencyContacts []emergencyContactView `json:"emergency_contacts"`
}

// ---- waiting for the team indexes ----------------------------------------------
//
// A team's roster, pending invitations and receivers are read through
// eventually consistent indexes. In-process they settle at once; on dev a read
// made the instant after a write can still see the row as it was. So a step
// that changes one waits until the index shows the change before the next step
// reads it, and fails if it never does.

func eventually(ctx context.Context, what string, settled func(context.Context) (bool, error)) error {
	deadline := time.Now().Add(10 * time.Second)
	for {
		ok, err := settled(ctx)
		if err != nil {
			return err
		}
		if ok {
			return nil
		}
		if time.Now().After(deadline) {
			return fmt.Errorf("waited 10s for %s, and it never showed", what)
		}
		time.Sleep(200 * time.Millisecond)
	}
}

// awaitRoster waits until the team's roster shows userID in role, or not at
// all when role is "".
func (w *world) awaitRoster(ctx context.Context, teamID, userID, role string) error {
	return eventually(ctx, fmt.Sprintf("the roster of %s to show %s as %q", teamID, userID, role), func(ctx context.Context) (bool, error) {
		ms, err := w.d.db().stores().Memberships.ListByTeam(ctx, teamID)
		if err != nil {
			return false, err
		}
		for _, m := range ms {
			if m.UserID == userID {
				return string(m.Role) == role, nil
			}
		}
		return role == "", nil
	})
}

// awaitPending waits until the team's pending invitations do, or do not,
// hold code.
func (w *world) awaitPending(ctx context.Context, teamID, code string, pending bool) error {
	return eventually(ctx, fmt.Sprintf("the invitation %s to be pending=%v", code, pending), func(ctx context.Context) (bool, error) {
		invs, err := w.d.db().stores().Invitations.ListPendingByTeam(ctx, teamID)
		if err != nil {
			return false, err
		}
		for _, inv := range invs {
			if inv.Code == code {
				return pending, nil
			}
		}
		return !pending, nil
	})
}

// awaitReceiver waits until the team's receivers with status hold rc as it
// now is, by name and time zone.
func (w *world) awaitReceiver(ctx context.Context, rc domain.Receiver, status domain.ReceiverStatus) error {
	return eventually(ctx, fmt.Sprintf("the receiver %s to be listed %s", rc.ReceiverID, status), func(ctx context.Context) (bool, error) {
		rs, err := w.d.db().stores().Receivers.ListByTeam(ctx, rc.TeamID, status)
		if err != nil {
			return false, err
		}
		for _, r := range rs {
			if r.ReceiverID == rc.ReceiverID {
				return r.Name == rc.Name && r.TimeZone == rc.TimeZone, nil
			}
		}
		return false, nil
	})
}

// ---- who is on the team -------------------------------------------------------

// hasJoinedAs puts someone who has used the app on the team in a role, as
// though they had redeemed an invitation and, for an admin, been promoted.
func (w *world) hasJoinedAs(ctx context.Context, label, team, role string) error {
	p, err := w.signedIn(ctx, label)
	if err != nil {
		return err
	}
	id, err := w.teamID(team)
	if err != nil {
		return err
	}
	w.track(membershipKey(w.d.db().names, p.userID, id))
	if err := w.d.db().putMembership(ctx, domain.NewMembership(p.userID, id, domain.Role(role), time.Now().UTC())); err != nil {
		return err
	}
	return w.awaitRoster(ctx, id, p.userID, role)
}

func (w *world) opensTeam(ctx context.Context, label, team string) error {
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	id, err := w.teamID(team)
	if err != nil {
		return err
	}
	if err := w.call(ctx, p, http.MethodGet, "/v1/teams/"+id, nil); err != nil {
		return err
	}
	w.team.detail = nil
	if w.last.status == http.StatusOK {
		d, err := decodeLast[teamDetailView](w)
		if err != nil {
			return err
		}
		w.team.detail = &d
	}
	return nil
}

// caregiversAre checks everyone on the roster and the role each holds. The
// PRD says who is listed and what they hold, not in what order, so neither
// does this.
func (w *world) caregiversAre(t *godog.Table) error {
	if w.team.detail == nil {
		return w.unexpected("the care team to load (200)")
	}
	var want, got []string
	for _, row := range table(t) {
		want = append(want, row["name"]+" as "+row["role"])
	}
	for _, m := range w.team.detail.Members {
		got = append(got, m.Name+" as "+m.Role)
	}
	sort.Strings(want)
	sort.Strings(got)
	if strings.Join(got, "|") != strings.Join(want, "|") {
		return fmt.Errorf("expected the care team's caregivers to be %q, but they were %q", want, got)
	}
	return nil
}

func (w *world) memberPath(ctx context.Context, label, team string) (string, error) {
	p, err := w.person(ctx, label)
	if err != nil {
		return "", err
	}
	id, err := w.teamID(team)
	if err != nil {
		return "", err
	}
	return "/v1/teams/" + id + "/members/" + p.userID, nil
}

func (w *world) makesRole(ctx context.Context, by, label, role, team string) error {
	p, err := w.person(ctx, by)
	if err != nil {
		return err
	}
	path, err := w.memberPath(ctx, label, team)
	if err != nil {
		return err
	}
	if err := w.call(ctx, p, http.MethodPut, path, map[string]string{"role": role}); err != nil {
		return err
	}
	if w.last.status != http.StatusOK {
		return nil
	}
	return w.awaitRoster(ctx, w.teams[team], w.people[label].userID, role)
}

func (w *world) removesFrom(ctx context.Context, by, label, team string) error {
	p, err := w.person(ctx, by)
	if err != nil {
		return err
	}
	path, err := w.memberPath(ctx, label, team)
	if err != nil {
		return err
	}
	if err := w.call(ctx, p, http.MethodDelete, path, nil); err != nil {
		return err
	}
	if w.last.status != http.StatusNoContent {
		return nil
	}
	return w.awaitRoster(ctx, w.teams[team], w.people[label].userID, "")
}

func (w *world) leaves(ctx context.Context, label, team string) error {
	return w.removesFrom(ctx, label, label, team)
}

func (w *world) closes(ctx context.Context, label, team string) error {
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	id, err := w.teamID(team)
	if err != nil {
		return err
	}
	return w.call(ctx, p, http.MethodPost, "/v1/teams/"+id+"/close", nil)
}

// ---- invitations made in the app ------------------------------------------------

func (w *world) invitesThroughApp(ctx context.Context, by, invitee, team string) error {
	p, err := w.person(ctx, by)
	if err != nil {
		return err
	}
	who, err := w.person(ctx, invitee)
	if err != nil {
		return err
	}
	id, err := w.teamID(team)
	if err != nil {
		return err
	}
	if err := w.call(ctx, p, http.MethodPost, "/v1/teams/"+id+"/invitations", map[string]string{"email": who.email}); err != nil {
		return err
	}
	if w.last.status == http.StatusCreated {
		inv, err := decodeLast[teamInvitationView](w)
		if err != nil {
			return err
		}
		w.track(invitationKey(w.d.db().names, inv.Code))
		w.team.invited[who.email] = inv.Code
		w.codes[team] = inv.Code
		return w.awaitPending(ctx, id, inv.Code, true)
	}
	return nil
}

func (w *world) opensPending(ctx context.Context, label, team string) error {
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	id, err := w.teamID(team)
	if err != nil {
		return err
	}
	if err := w.call(ctx, p, http.MethodGet, "/v1/teams/"+id+"/invitations", nil); err != nil {
		return err
	}
	w.team.pending = nil
	if w.last.status == http.StatusOK {
		invs, err := decodeLast[[]teamInvitationView](w)
		if err != nil {
			return err
		}
		w.team.pending = invs
	}
	return nil
}

func (w *world) pendingAreFor(list string) error {
	if w.last.status != http.StatusOK {
		return w.unexpected("the pending invitations to load (200)")
	}
	var want, got []string
	for _, label := range names(list) {
		p := w.people[label]
		if p == nil {
			return fmt.Errorf("%q has not appeared in this scenario", label)
		}
		want = append(want, p.email+" "+w.team.invited[p.email])
	}
	for _, inv := range w.team.pending {
		got = append(got, inv.Email+" "+inv.Code)
	}
	sort.Strings(want)
	sort.Strings(got)
	if strings.Join(got, "|") != strings.Join(want, "|") {
		return fmt.Errorf("expected the invitations pending (address and code) to be %q, but they were %q", want, got)
	}
	return nil
}

func (w *world) noInvitationsPending() error {
	if w.last.status != http.StatusOK {
		return w.unexpected("the pending invitations to load (200)")
	}
	if w.team.pending == nil || len(w.team.pending) != 0 {
		return w.unexpected("no invitations to be pending (an empty list)")
	}
	return nil
}

// ---- notification choices --------------------------------------------------------

func (w *world) notificationChoices(ctx context.Context, label, team string) (*person, string, notificationChoicesView, error) {
	p, err := w.person(ctx, label)
	if err != nil {
		return nil, "", nil, err
	}
	id, err := w.teamID(team)
	if err != nil {
		return nil, "", nil, err
	}
	path := "/v1/teams/" + id + "/my-notifications"
	if err := w.call(ctx, p, http.MethodGet, path, nil); err != nil {
		return nil, "", nil, err
	}
	if w.last.status != http.StatusOK {
		return nil, "", nil, w.unexpected(fmt.Sprintf("%q's notification choices for %q to load (200)", label, w.teamName(team)))
	}
	c, err := decodeLast[notificationChoicesView](w)
	return p, path, c, err
}

// turnsNotification is Team notification settings' switch: the choices as
// they stand, with one kind turned on or off.
func (w *world) turnsNotification(ctx context.Context, label, onOff, kind, team string) error {
	p, path, c, err := w.notificationChoices(ctx, label, team)
	if err != nil {
		return err
	}
	c[notificationKinds[kind]] = onOff == "on"
	if err := w.call(ctx, p, http.MethodPut, path, c); err != nil {
		return err
	}
	if w.last.status != http.StatusOK {
		return w.unexpected(fmt.Sprintf("%q to turn %s %s for %q (200)", label, onOff, kind, w.teamName(team)))
	}
	return nil
}

func (w *world) getsNotification(ctx context.Context, label, gets, kind, team string) error {
	_, _, c, err := w.notificationChoices(ctx, label, team)
	if err != nil {
		return err
	}
	on, ok := c[notificationKinds[kind]]
	if !ok || on != (gets == "gets") {
		return w.unexpected(fmt.Sprintf("%q to %s %s from %q", label, map[bool]string{true: "get", false: "not get"}[gets == "gets"], kind, w.teamName(team)))
	}
	return nil
}

// ---- care receivers ----------------------------------------------------------------

func (w *world) addsReceiver(ctx context.Context, label, receiver, team, tz string) error {
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	id, err := w.teamID(team)
	if err != nil {
		return err
	}
	body := map[string]string{"name": receiver + " " + w.suffix, "time_zone": tz}
	if err := w.call(ctx, p, http.MethodPost, "/v1/teams/"+id+"/receivers", body); err != nil {
		return err
	}
	if w.last.status == http.StatusCreated {
		rc, err := decodeLast[careReceiverView](w)
		if err != nil {
			return err
		}
		w.track(receiverKey(w.d.db().names, rc.ReceiverID))
		made := domain.Receiver{
			ReceiverID: rc.ReceiverID, TeamID: rc.TeamID, Name: rc.Name, TimeZone: rc.TimeZone, Status: domain.ReceiverActive,
		}
		w.care.receivers[receiver] = made
		return w.awaitReceiver(ctx, made, domain.ReceiverActive)
	}
	return nil
}

func (w *world) opensArchivedReceivers(ctx context.Context, label, team string) error {
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	id, err := w.teamID(team)
	if err != nil {
		return err
	}
	if err := w.call(ctx, p, http.MethodGet, "/v1/teams/"+id+"/receivers?status=archived", nil); err != nil {
		return err
	}
	w.care.receiverList = nil
	if w.last.status == http.StatusOK {
		rows, err := decodeLast[[]receiverView](w)
		if err != nil {
			return err
		}
		w.care.receiverList = rows
	}
	return nil
}

func (w *world) noReceiversListed() error {
	if w.last.status != http.StatusOK {
		return w.unexpected("the care receivers to load (200)")
	}
	if len(w.care.receiverList) != 0 {
		return w.unexpected("no care receivers to be listed")
	}
	return nil
}

// changeReceiver is Edit care receiver's Save: name and time zone together.
func (w *world) changeReceiver(ctx context.Context, label, receiver, name, tz string) error {
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	rc, err := w.receiver(receiver)
	if err != nil {
		return err
	}
	if err := w.call(ctx, p, http.MethodPut, "/v1/receivers/"+rc.ReceiverID, map[string]string{"name": name, "time_zone": tz}); err != nil {
		return err
	}
	if w.last.status == http.StatusOK {
		rc.Name, rc.TimeZone = name, tz
		w.care.receivers[receiver] = rc
		return w.awaitReceiver(ctx, rc, domain.ReceiverActive)
	}
	return nil
}

func (w *world) renamesReceiver(ctx context.Context, label, receiver, name string) error {
	rc, err := w.receiver(receiver)
	if err != nil {
		return err
	}
	if err := w.changeReceiver(ctx, label, receiver, name+" "+w.suffix, rc.TimeZone); err != nil {
		return err
	}
	if w.last.status == http.StatusOK {
		w.care.receivers[name] = w.care.receivers[receiver]
	}
	return nil
}

func (w *world) movesReceiver(ctx context.Context, label, receiver, tz string) error {
	rc, err := w.receiver(receiver)
	if err != nil {
		return err
	}
	return w.changeReceiver(ctx, label, receiver, rc.Name, tz)
}

func (w *world) archivesReceiver(ctx context.Context, label, verb, receiver string) error {
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	rc, err := w.receiver(receiver)
	if err != nil {
		return err
	}
	action, status := "archive", domain.ReceiverArchived
	if verb == "restores" {
		action, status = "restore", domain.ReceiverActive
	}
	if err := w.call(ctx, p, http.MethodPost, "/v1/receivers/"+rc.ReceiverID+"/"+action, nil); err != nil {
		return err
	}
	if w.last.status != http.StatusNoContent {
		return nil
	}
	rc.Status = status
	w.care.receivers[receiver] = rc
	return w.awaitReceiver(ctx, rc, status)
}

func (w *world) opensReceiver(ctx context.Context, label, receiver string) error {
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	rc, err := w.receiver(receiver)
	if err != nil {
		return err
	}
	if err := w.call(ctx, p, http.MethodGet, "/v1/receivers/"+rc.ReceiverID, nil); err != nil {
		return err
	}
	return w.keepReceiver()
}

// keepReceiver keeps the Care receiver screen a 200 answered with, which a
// read and every care-instructions write return.
func (w *world) keepReceiver() error {
	w.team.receiver = nil
	if w.last.status != http.StatusOK {
		return nil
	}
	rc, err := decodeLast[careReceiverView](w)
	if err != nil {
		return err
	}
	w.team.receiver = &rc
	return nil
}

func (w *world) shownReceiver() (*careReceiverView, error) {
	if w.team.receiver == nil {
		return nil, w.unexpected("the care receiver to load (200)")
	}
	return w.team.receiver, nil
}

func (w *world) receiverIs(name, team, tz string) error {
	rc, err := w.shownReceiver()
	if err != nil {
		return err
	}
	if rc.Name != name+" "+w.suffix || rc.TeamName != w.teamName(team) || rc.TimeZone != tz {
		return w.unexpected(fmt.Sprintf("the care receiver %q of %q, keeping time in %q", name, w.teamName(team), tz))
	}
	return nil
}

func (w *world) receiverReadsAs(status string) error {
	rc, err := w.shownReceiver()
	if err != nil {
		return err
	}
	if rc.Status != status {
		return w.unexpected(fmt.Sprintf("the care receiver to read as %s", status))
	}
	return nil
}

func (w *world) noInstructionsYet() error {
	rc, err := w.shownReceiver()
	if err != nil {
		return err
	}
	if rc.CareInstructions != nil {
		return w.unexpected("no care instructions yet")
	}
	return nil
}

func (w *world) instructionsRead(body, by string) error {
	rc, err := w.shownReceiver()
	if err != nil {
		return err
	}
	want := fmt.Sprintf("the care instructions to read %q, last changed by %q just now", body, by)
	ci := rc.CareInstructions
	if ci == nil || ci.Body != body || ci.UpdatedByName != by {
		return w.unexpected(want)
	}
	at, err := time.Parse(time.RFC3339, ci.UpdatedAt)
	if err != nil || time.Since(at) > 5*time.Minute || time.Until(at) > time.Minute {
		return w.unexpected(want)
	}
	return nil
}

func (w *world) noContactsYet() error {
	rc, err := w.shownReceiver()
	if err != nil {
		return err
	}
	if rc.EmergencyContacts == nil || len(rc.EmergencyContacts) != 0 {
		return w.unexpected("no emergency contacts yet (an empty list)")
	}
	return nil
}

func contactLine(name, relationship, phone string) string {
	return name + " (" + relationship + ") " + phone
}

func (w *world) contactsAre(t *godog.Table) error {
	rc, err := w.shownReceiver()
	if err != nil {
		return err
	}
	var want, got []string
	for _, row := range table(t) {
		want = append(want, contactLine(row["name"], row["relationship"], row["phone"]))
	}
	for _, c := range rc.EmergencyContacts {
		got = append(got, contactLine(c.Name, c.Relationship, c.Phone))
	}
	if strings.Join(got, "\n") != strings.Join(want, "\n") {
		return fmt.Errorf("expected the emergency contacts, in order:\n  %s\nbut they were:\n  %s",
			strings.Join(want, "\n  "), strings.Join(got, "\n  "))
	}
	return nil
}

// ---- writing care instructions and emergency contacts ------------------------------

func (w *world) careWrite(ctx context.Context, label, receiver, what string, body any) error {
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	rc, err := w.receiver(receiver)
	if err != nil {
		return err
	}
	// Deleting a row that was never written is harmless, so track it whatever
	// the answer.
	w.track(careInstructionsKey(w.d.db().names, rc.ReceiverID))
	if err := w.call(ctx, p, http.MethodPut, "/v1/receivers/"+rc.ReceiverID+"/"+what, body); err != nil {
		return err
	}
	return w.keepReceiver()
}

func (w *world) writesInstructions(ctx context.Context, label, receiver, body string) error {
	return w.careWrite(ctx, label, receiver, "care-instructions", map[string]string{"body": body})
}

func (w *world) clearsInstructions(ctx context.Context, label, receiver string) error {
	return w.careWrite(ctx, label, receiver, "care-instructions", map[string]string{"body": ""})
}

// setsContacts is the Emergency contacts sheet's Save: the whole list, in the
// order given. A contact already on the receiver (by name) is sent with its
// id, as the sheet keeps it; the rest are new.
func (w *world) setsContacts(ctx context.Context, label, receiver string, t *godog.Table) error {
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	rc, err := w.receiver(receiver)
	if err != nil {
		return err
	}
	ids := map[string]string{}
	if err := w.call(ctx, p, http.MethodGet, "/v1/receivers/"+rc.ReceiverID, nil); err != nil {
		return err
	}
	if w.last.status == http.StatusOK {
		cur, err := decodeLast[careReceiverView](w)
		if err != nil {
			return err
		}
		for _, c := range cur.EmergencyContacts {
			ids[c.Name] = c.ContactID
		}
	}
	contacts := []map[string]string{}
	for _, row := range table(t) {
		c := map[string]string{"name": row["name"], "relationship": row["relationship"], "phone": row["phone"]}
		if id := ids[row["name"]]; id != "" {
			c["contact_id"] = id
		}
		contacts = append(contacts, c)
	}
	return w.careWrite(ctx, label, receiver, "emergency-contacts", map[string]any{"contacts": contacts})
}

// ---- a time zone and the routines in it ---------------------------------------------

// nextComingUpAt checks the tracker's next scheduled entry, as Coming up last
// showed it, falls at a wall-clock time in a zone.
func (w *world) nextComingUpAt(tracker, hhmm, tz string) error {
	if w.last.status != http.StatusOK {
		return w.unexpected("coming up to load (200)")
	}
	loc, err := time.LoadLocation(tz)
	if err != nil {
		return err
	}
	for _, it := range w.home.items {
		if it.Tracker.Name != tracker {
			continue
		}
		at, err := time.Parse(time.RFC3339, it.Entry.At)
		if err != nil {
			return w.unexpected(fmt.Sprintf("a time for the next %q (%v)", tracker, err))
		}
		if got := at.In(loc).Format("15:04"); got != hhmm {
			return fmt.Errorf("expected the next %q due at %s in %s, but it is due at %s there (%s)", tracker, hhmm, tz, got, it.Entry.At)
		}
		return nil
	}
	return w.unexpected(fmt.Sprintf("coming up to hold the next %q", tracker))
}
