package features_test

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/cucumber/godog"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
)

// world is one scenario's state: who is in it, the care teams and invite
// codes it made, and the last answer the API gave.
type world struct {
	d      driver
	suffix string
	people map[string]*person
	order  []*person
	teams  map[string]string // care team name as written in the feature → team_id
	codes  map[string]string // care team name → the invite code most recently made for it
	last   answer
	rows   []rowKey
	n      int
	care   careWorld
	home   homeWorld
}

func newWorld(d driver, suffix string) *world {
	return &world{
		d: d, suffix: suffix, people: map[string]*person{}, teams: map[string]string{}, codes: map[string]string{},
		care: newCareWorld(),
	}
}

func (w *world) register(sc *godog.ScenarioContext) {
	sc.Step(`^"([^"]*)" signs in$`, w.signsIn)
	sc.Step(`^someone who has not signed in asks for their account$`, w.anonymousAsksForAccount)
	sc.Step(`^"([^"]*)" has closed their account$`, w.hasClosedTheirAccount)

	sc.Step(`^"([^"]*)" has created the care team "([^"]*)"$`, w.hasCreatedTeam)
	sc.Step(`^"([^"]*)" creates a care team named "([^"]*)"$`, w.createsTeamNamed)
	sc.Step(`^"([^"]*)" creates a care team whose name is (\d+) characters long$`, w.createsTeamWithNameLength)
	sc.Step(`^"([^"]*)" has been closed$`, w.teamHasBeenClosed)
	sc.Step(`^"([^"]*)" is already a caregiver on "([^"]*)"$`, w.isAlreadyCaregiverOn)

	sc.Step(`^"([^"]*)" has invited "([^"]*)" to "([^"]*)"$`, w.hasInvited)
	sc.Step(`^"([^"]*)" has invited a different email address than "([^"]*)"'s to "([^"]*)"$`, w.hasInvitedDifferentEmail)
	sc.Step(`^the invite code for "([^"]*)" (was never issued|has expired|has already been used|has been revoked)$`, w.inviteCodeIsBad)
	sc.Step(`^"([^"]*)" accepts their invitation to "([^"]*)"$`, w.acceptsInvitation)
	sc.Step(`^"([^"]*)" pastes the invite code for "([^"]*)"$`, w.pastesCode)

	sc.Step(`^the answer is (\d+)$`, w.answerIs)
	sc.Step(`^the answer is (\d+) "([^"]*)"$`, w.answerIsWithMessage)
	sc.Step(`^the answer is (\d+) "([^"]*)" and nothing more$`, w.answerIsExactly)
	sc.Step(`^the answer lists no care teams$`, w.answerListsNoTeams)
	sc.Step(`^the answer shows "([^"]*)"'s name and email address$`, w.answerShowsNameAndEmail)
	sc.Step(`^the new care team is called "([^"]*)"$`, w.newTeamIsCalled)
	sc.Step(`^"([^"]*)" belongs to "([^"]*)" as an? (admin|caregiver)$`, w.belongsToAs)
	sc.Step(`^"([^"]*)" belongs to no care team$`, w.belongsToNoTeam)
	sc.Step(`^"([^"]*)" does not belong to "([^"]*)"$`, w.doesNotBelongTo)
	sc.Step(`^"([^"]*)" has a pending invitation to "([^"]*)" from "([^"]*)"$`, w.hasPendingInvitationFrom)
	sc.Step(`^"([^"]*)" has no pending invitations$`, w.hasNoPendingInvitations)

	w.registerTrackers(sc)
	w.registerHome(sc)

	// Clean up whatever happened: a failed scenario still deletes what it made.
	// A step's own failure is already recorded; this only adds a cleanup failure.
	sc.After(func(ctx context.Context, _ *godog.Scenario, _ error) (context.Context, error) {
		cctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
		defer cancel()
		genErr := w.trackGenerated(cctx)
		if err := errors.Join(genErr, w.d.cleanup(cctx, w.rows, w.order)); err != nil {
			return ctx, fmt.Errorf("cleanup failed: %w", err)
		}
		return ctx, nil
	})
}

// ---- people, teams, and names ----------------------------------------------

func (w *world) email(label string) string {
	return fmt.Sprintf("features.%s.%s@example.com", strings.ToLower(strings.ReplaceAll(label, " ", "-")), w.suffix)
}

// person returns the named person, giving them an identity on first mention.
func (w *world) person(ctx context.Context, label string) (*person, error) {
	if p, ok := w.people[label]; ok {
		return p, nil
	}
	p := &person{label: label, email: w.email(label)}
	if err := w.d.newPerson(ctx, p); err != nil {
		return nil, fmt.Errorf("could not give %q an identity: %w", label, err)
	}
	w.people[label] = p
	w.order = append(w.order, p)
	w.track(userKey(w.d.db().names, p.userID))
	return p, nil
}

// teamName is the name actually sent for a care team: the feature's name plus
// the scenario's suffix, so leftovers on dev can be found by suffix.
func (w *world) teamName(name string) string { return name + " " + w.suffix }

func (w *world) teamID(name string) (string, error) {
	id, ok := w.teams[name]
	if !ok {
		return "", fmt.Errorf("the scenario never created a care team called %q", name)
	}
	return id, nil
}

func (w *world) track(k rowKey) { w.rows = append(w.rows, k) }

func (w *world) call(ctx context.Context, p *person, method, path string, body any) error {
	a, err := w.d.call(ctx, p, method, path, body)
	if err != nil {
		return fmt.Errorf("could not reach the API for %s %s: %w", method, path, err)
	}
	w.last = a
	return nil
}

// unexpected describes the last answer against what was expected.
func (w *world) unexpected(expected string) error {
	return fmt.Errorf("expected %s\n  but %s answered %d %s", expected, w.last.request, w.last.status, compact(w.last.body))
}

func compact(b []byte) string {
	var buf bytes.Buffer
	if json.Compact(&buf, b) == nil {
		return buf.String()
	}
	return string(b)
}

// ---- API shapes -------------------------------------------------------------

type teamMembership struct {
	TeamID string `json:"team_id"`
	Name   string `json:"name"`
	Role   string `json:"role"`
}

type myAccount struct {
	Caregiver struct {
		UserID string `json:"user_id"`
		Email  string `json:"email"`
		Name   string `json:"name"`
	} `json:"caregiver"`
	Teams []teamMembership `json:"teams"`
}

type invitationForMe struct {
	Code          string `json:"code"`
	TeamID        string `json:"team_id"`
	TeamName      string `json:"team_name"`
	InvitedByName string `json:"invited_by_name"`
}

func decodeLast[T any](w *world) (T, error) {
	var v T
	if err := json.Unmarshal(w.last.body, &v); err != nil {
		return v, w.unexpected(fmt.Sprintf("a JSON answer (%v)", err))
	}
	return v, nil
}

// ---- signing in -------------------------------------------------------------

func (w *world) signsIn(ctx context.Context, label string) error {
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	return w.call(ctx, p, http.MethodGet, "/v1/me", nil)
}

func (w *world) anonymousAsksForAccount(ctx context.Context) error {
	return w.call(ctx, nil, http.MethodGet, "/v1/me", nil)
}

// account fetches the person's account, requiring a 200.
func (w *world) account(ctx context.Context, label string) (myAccount, error) {
	if err := w.signsIn(ctx, label); err != nil {
		return myAccount{}, err
	}
	if w.last.status != http.StatusOK {
		return myAccount{}, w.unexpected(fmt.Sprintf("%q's account to load (200)", label))
	}
	return decodeLast[myAccount](w)
}

func (w *world) hasClosedTheirAccount(ctx context.Context, label string) error {
	// They must have signed in once for there to be an account to close.
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	if _, err := w.account(ctx, label); err != nil {
		return err
	}
	return w.d.db().closeAccount(ctx, p.userID, time.Now())
}

// ---- care teams -------------------------------------------------------------

func (w *world) createTeam(ctx context.Context, label, rawName string) error {
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	name := strings.TrimSpace(rawName)
	sent := rawName
	if name != "" {
		sent = strings.Replace(rawName, name, w.teamName(name), 1)
	}
	if err := w.call(ctx, p, http.MethodPost, "/v1/teams", map[string]string{"name": sent}); err != nil {
		return err
	}
	if w.last.status == http.StatusCreated {
		tm, err := decodeLast[teamMembership](w)
		if err != nil {
			return err
		}
		w.teams[name] = tm.TeamID
		names := w.d.db().names
		w.track(teamKey(names, tm.TeamID))
		w.track(membershipKey(names, p.userID, tm.TeamID))
	}
	return nil
}

func (w *world) hasCreatedTeam(ctx context.Context, label, name string) error {
	if err := w.createTeam(ctx, label, name); err != nil {
		return err
	}
	if w.last.status != http.StatusCreated {
		return w.unexpected(fmt.Sprintf("%q to create the care team %q (201)", label, name))
	}
	return nil
}

func (w *world) createsTeamNamed(ctx context.Context, label, name string) error {
	return w.createTeam(ctx, label, name)
}

func (w *world) createsTeamWithNameLength(ctx context.Context, label string, n int) error {
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	return w.call(ctx, p, http.MethodPost, "/v1/teams", map[string]string{"name": strings.Repeat("a", n)})
}

func (w *world) newTeamIsCalled(name string) error {
	tm, err := decodeLast[teamMembership](w)
	if err != nil {
		return err
	}
	if tm.Name != w.teamName(name) {
		return w.unexpected(fmt.Sprintf("the new care team to be called %q", w.teamName(name)))
	}
	return nil
}

func (w *world) teamHasBeenClosed(ctx context.Context, name string) error {
	id, err := w.teamID(name)
	if err != nil {
		return err
	}
	return w.d.db().closeTeam(ctx, id, "features", time.Now())
}

func (w *world) isAlreadyCaregiverOn(ctx context.Context, label, name string) error {
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	id, err := w.teamID(name)
	if err != nil {
		return err
	}
	w.track(membershipKey(w.d.db().names, p.userID, id))
	return w.d.db().putMembership(ctx, domain.NewMembership(p.userID, id, domain.RoleCaregiver, time.Now().UTC()))
}

func (w *world) belongsToAs(ctx context.Context, label, name, role string) error {
	acct, err := w.account(ctx, label)
	if err != nil {
		return err
	}
	id, err := w.teamID(name)
	if err != nil {
		return err
	}
	for _, t := range acct.Teams {
		if t.TeamID == id {
			if t.Name != w.teamName(name) || t.Role != role {
				return w.unexpected(fmt.Sprintf("%q to belong to %q as %s", label, w.teamName(name), role))
			}
			return nil
		}
	}
	return w.unexpected(fmt.Sprintf("%q's account to list the care team %q", label, w.teamName(name)))
}

func (w *world) belongsToNoTeam(ctx context.Context, label string) error {
	acct, err := w.account(ctx, label)
	if err != nil {
		return err
	}
	if len(acct.Teams) != 0 {
		return w.unexpected(fmt.Sprintf("%q to belong to no care team", label))
	}
	return nil
}

func (w *world) doesNotBelongTo(ctx context.Context, label, name string) error {
	acct, err := w.account(ctx, label)
	if err != nil {
		return err
	}
	id, err := w.teamID(name)
	if err != nil {
		return err
	}
	for _, t := range acct.Teams {
		if t.TeamID == id {
			return w.unexpected(fmt.Sprintf("%q not to belong to %q", label, w.teamName(name)))
		}
	}
	return nil
}

// ---- invitations ------------------------------------------------------------

// invite writes a pending invitation straight to the table: no endpoint
// creates invitations yet.
func (w *world) invite(ctx context.Context, inviterLabel, email, team string) error {
	inviter, err := w.person(ctx, inviterLabel)
	if err != nil {
		return err
	}
	id, err := w.teamID(team)
	if err != nil {
		return err
	}
	w.n++
	code := fmt.Sprintf("features-%s-%d", w.suffix, w.n)
	now := time.Now().UTC()
	w.track(invitationKey(w.d.db().names, code))
	if err := w.d.db().putInvitation(ctx, domain.Invitation{
		Code: code, TeamID: id, Email: email, Status: domain.InvitePending, InvitedBy: inviter.userID,
		CreatedAt: now, ExpiresAt: now.Add(14 * 24 * time.Hour).Unix(),
	}); err != nil {
		return fmt.Errorf("could not write the invitation: %w", err)
	}
	w.codes[team] = code
	return nil
}

func (w *world) hasInvited(ctx context.Context, inviter, invitee, team string) error {
	p, err := w.person(ctx, invitee)
	if err != nil {
		return err
	}
	return w.invite(ctx, inviter, p.email, team)
}

func (w *world) hasInvitedDifferentEmail(ctx context.Context, inviter, invitee, team string) error {
	if _, err := w.person(ctx, invitee); err != nil {
		return err
	}
	return w.invite(ctx, inviter, w.email("someone-else"), team)
}

func (w *world) inviteCodeIsBad(ctx context.Context, team, problem string) error {
	code, ok := w.codes[team]
	if !ok {
		return fmt.Errorf("no invite code was made for %q", team)
	}
	db := w.d.db()
	switch problem {
	case "was never issued":
		w.codes[team] = fmt.Sprintf("features-%s-never-issued", w.suffix)
		return nil
	case "has expired":
		return db.setInvitationExpiry(ctx, code, time.Now().Add(-time.Hour))
	case "has already been used":
		return db.setInvitationStatus(ctx, code, domain.InviteAccepted)
	case "has been revoked":
		return db.setInvitationStatus(ctx, code, domain.InviteRevoked)
	}
	return fmt.Errorf("unknown invite code problem %q", problem)
}

func (w *world) pendingInvitations(ctx context.Context, label string) ([]invitationForMe, error) {
	p, err := w.person(ctx, label)
	if err != nil {
		return nil, err
	}
	if err := w.call(ctx, p, http.MethodGet, "/v1/me/invitations", nil); err != nil {
		return nil, err
	}
	if w.last.status != http.StatusOK {
		return nil, w.unexpected(fmt.Sprintf("%q's pending invitations to load (200)", label))
	}
	return decodeLast[[]invitationForMe](w)
}

func (w *world) hasPendingInvitationFrom(ctx context.Context, label, team, from string) error {
	invs, err := w.pendingInvitations(ctx, label)
	if err != nil {
		return err
	}
	id, err := w.teamID(team)
	if err != nil {
		return err
	}
	want := fmt.Sprintf("%q to have a pending invitation to %q from %q", label, w.teamName(team), from)
	for _, inv := range invs {
		if inv.TeamID == id {
			if inv.TeamName != w.teamName(team) || inv.InvitedByName != from {
				return w.unexpected(want)
			}
			return nil
		}
	}
	return w.unexpected(want)
}

func (w *world) hasNoPendingInvitations(ctx context.Context, label string) error {
	invs, err := w.pendingInvitations(ctx, label)
	if err != nil {
		return err
	}
	if len(invs) != 0 {
		return w.unexpected(fmt.Sprintf("%q to have no pending invitations", label))
	}
	return nil
}

func (w *world) redeem(ctx context.Context, p *person, team, code string) error {
	if err := w.call(ctx, p, http.MethodPost, "/v1/invitations/redeem", map[string]string{"code": code}); err != nil {
		return err
	}
	if w.last.status == http.StatusOK {
		if id, ok := w.teams[team]; ok {
			w.track(membershipKey(w.d.db().names, p.userID, id))
		}
	}
	return nil
}

// acceptsInvitation is the in-app path: find the invitation in the list, then redeem its code.
func (w *world) acceptsInvitation(ctx context.Context, label, team string) error {
	invs, err := w.pendingInvitations(ctx, label)
	if err != nil {
		return err
	}
	id, err := w.teamID(team)
	if err != nil {
		return err
	}
	for _, inv := range invs {
		if inv.TeamID == id {
			return w.redeem(ctx, w.people[label], team, inv.Code)
		}
	}
	return w.unexpected(fmt.Sprintf("%q to see an invitation to %q to accept", label, w.teamName(team)))
}

// pastesCode is the other path: the code the admin sent, typed in.
func (w *world) pastesCode(ctx context.Context, label, team string) error {
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	code, ok := w.codes[team]
	if !ok {
		return fmt.Errorf("no invite code was made for %q", team)
	}
	return w.redeem(ctx, p, team, code)
}

// ---- the answer -------------------------------------------------------------

func (w *world) answerIs(status int) error {
	if w.last.status != status {
		return w.unexpected(fmt.Sprintf("the answer to be %d", status))
	}
	return nil
}

func (w *world) answerIsWithMessage(status int, msg string) error {
	want := fmt.Sprintf("the answer to be %d %q", status, msg)
	if w.last.status != status {
		return w.unexpected(want)
	}
	var body struct {
		Message string `json:"message"`
	}
	if json.Unmarshal(w.last.body, &body) != nil || body.Message != msg {
		return w.unexpected(want)
	}
	return nil
}

// answerIsExactly also requires that the body says nothing beyond the message,
// so every refused code gets the very same answer.
func (w *world) answerIsExactly(status int, msg string) error {
	if err := w.answerIsWithMessage(status, msg); err != nil {
		return err
	}
	var body map[string]any
	if json.Unmarshal(w.last.body, &body) != nil || len(body) != 1 {
		return w.unexpected(fmt.Sprintf("the answer to be %d %q and nothing more", status, msg))
	}
	return nil
}

func (w *world) answerListsNoTeams() error {
	acct, err := decodeLast[myAccount](w)
	if err != nil {
		return err
	}
	if acct.Teams == nil || len(acct.Teams) != 0 {
		return w.unexpected("the answer to list no care teams (an empty list)")
	}
	return nil
}

func (w *world) answerShowsNameAndEmail(label string) error {
	acct, err := decodeLast[myAccount](w)
	if err != nil {
		return err
	}
	p := w.people[label]
	if p == nil {
		return fmt.Errorf("%q has not appeared in this scenario", label)
	}
	if acct.Caregiver.Name != p.label || acct.Caregiver.Email != p.email {
		return w.unexpected(fmt.Sprintf("the answer to show the name %q and the email %q", p.label, p.email))
	}
	return nil
}
