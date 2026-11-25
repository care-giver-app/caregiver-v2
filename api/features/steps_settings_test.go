package features_test

import (
	"context"
	"fmt"
	"net/http"
	"strings"

	"github.com/cucumber/godog"
)

// settingsWorld is what a Settings scenario remembers: the address a person
// asked to move to, keyed by their name as written.
type settingsWorld struct {
	newEmail map[string]string
}

func (w *world) registerSettings(sc *godog.ScenarioContext) {
	sc.Step(`^"([^"]*)" changes their name to "([^"]*)"$`, w.changesName)
	sc.Step(`^"([^"]*)" turns email notifications (on|off)$`, w.turnsEmailNotifications)
	sc.Step(`^"([^"]*)" saves their account with nothing changed$`, w.savesNothing)
	sc.Step(`^"([^"]*)"'s account shows the name "([^"]*)" with email notifications (on|off)$`, w.accountShows)

	sc.Step(`^"([^"]*)" asks to change their email to a new address with (their|a wrong) password$`, w.asksToChangeEmail)
	sc.Step(`^"([^"]*)" asks to change their email to "([^"]*)"'s address with their password$`, w.asksToChangeEmailToOthers)
	sc.Step(`^"([^"]*)" enters the code sent to the new address$`, w.entersCode)
	sc.Step(`^"([^"]*)"'s account shows (their new|their old) address$`, w.accountShowsAddress)

	sc.Step(`^"([^"]*)" closes their account with (their|a wrong) password$`, w.closesAccount)
	sc.Step(`^"([^"]*)" has tried a wrong password (\d+) times$`, w.triedWrongPassword)
	sc.Step(`^"([^"]*)" can no longer sign in$`, w.canNoLongerSignIn)
	sc.Step(`^the answer is 409, naming `+quoted+` as the care teams to promote someone on first$`, w.soleAdminNames)
	sc.Step(`^it asks to promote someone first on "([^"]*)"$`, func(team string) error { return w.soleAdminAlone(team, false) })
	sc.Step(`^it asks to close "([^"]*)" first, since nobody else is on it$`, func(team string) error { return w.soleAdminAlone(team, true) })

	sc.Step(`^"([^"]*)" sends (a bug report|a suggestion|feedback) reading "([^"]*)"( anonymously)?$`, w.sendsFeedback)
	sc.Step(`^"([^"]*)" sends feedback with no message$`, w.sendsEmptyFeedback)
	sc.Step(`^the people behind the app receive "([^"]*)" as (a bug report|a suggestion|feedback)$`, w.supportReceives)
	sc.Step(`^it goes with "([^"]*)"'s name and address$`, w.feedbackGoesWith)
	sc.Step(`^nothing that identifies "([^"]*)" goes with it$`, w.feedbackIdentifiesNobody)
	sc.Step(`^it goes with the app's version and the device$`, w.feedbackHasVersionAndDevice)
}

// ---- name and notifications --------------------------------------------------

type caregiverShape struct {
	UserID             string `json:"user_id"`
	Email              string `json:"email"`
	Name               string `json:"name"`
	EmailNotifications bool   `json:"email_notifications"`
}

func (w *world) patchMe(ctx context.Context, label string, body map[string]any) error {
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	return w.call(ctx, p, http.MethodPatch, "/v1/me", body)
}

func (w *world) changesName(ctx context.Context, label, name string) error {
	return w.patchMe(ctx, label, map[string]any{"name": name})
}

func (w *world) turnsEmailNotifications(ctx context.Context, label, onOff string) error {
	return w.patchMe(ctx, label, map[string]any{"email_notifications": onOff == "on"})
}

func (w *world) savesNothing(ctx context.Context, label string) error {
	return w.patchMe(ctx, label, map[string]any{})
}

func (w *world) myCaregiver(ctx context.Context, label string) (caregiverShape, error) {
	if err := w.signsIn(ctx, label); err != nil {
		return caregiverShape{}, err
	}
	if w.last.status != http.StatusOK {
		return caregiverShape{}, w.unexpected(fmt.Sprintf("%q's account to load (200)", label))
	}
	acct, err := decodeLast[struct {
		Caregiver caregiverShape `json:"caregiver"`
	}](w)
	return acct.Caregiver, err
}

func (w *world) accountShows(ctx context.Context, label, name, onOff string) error {
	c, err := w.myCaregiver(ctx, label)
	if err != nil {
		return err
	}
	if c.Name != name || c.EmailNotifications != (onOff == "on") {
		return w.unexpected(fmt.Sprintf("%q's account to show the name %q with email notifications %s", label, name, onOff))
	}
	return nil
}

// ---- change email -----------------------------------------------------------

func (w *world) password(p *person, which string) string {
	if which == "their" {
		return p.password
	}
	return p.password + "-wrong"
}

func (w *world) requestEmailChange(ctx context.Context, p *person, password, email string) error {
	return w.call(ctx, p, http.MethodPost, "/v1/me/email", map[string]string{"current_password": password, "new_email": email})
}

func (w *world) asksToChangeEmail(ctx context.Context, label, which string) error {
	p, err := w.signedIn(ctx, label)
	if err != nil {
		return err
	}
	if w.settings.newEmail == nil {
		w.settings.newEmail = map[string]string{}
	}
	email := w.email(label + "-new")
	w.settings.newEmail[label] = email
	return w.requestEmailChange(ctx, p, w.password(p, which), email)
}

func (w *world) asksToChangeEmailToOthers(ctx context.Context, label, other string) error {
	p, err := w.signedIn(ctx, label)
	if err != nil {
		return err
	}
	o, err := w.signedIn(ctx, other)
	if err != nil {
		return err
	}
	return w.requestEmailChange(ctx, p, p.password, o.email)
}

// inProcessOnly is the in-process driver, for steps that need what only it
// can see. Their scenarios are tagged @inprocess.
func (w *world) inProcessOnly() (*inProcess, error) {
	d, ok := w.d.(*inProcess)
	if !ok {
		return nil, fmt.Errorf("this step runs in-process only; tag its scenario @inprocess")
	}
	return d, nil
}

func (w *world) entersCode(ctx context.Context, label string) error {
	d, err := w.inProcessOnly()
	if err != nil {
		return err
	}
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	return d.identity.confirm(p)
}

func (w *world) accountShowsAddress(ctx context.Context, label, which string) error {
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	want := w.email(label)
	if which == "their new" {
		want = w.settings.newEmail[label]
	}
	c, err := w.myCaregiver(ctx, label)
	if err != nil {
		return err
	}
	if c.Email != want {
		return w.unexpected(fmt.Sprintf("%q's account to show %s", p.label, want))
	}
	return nil
}

// ---- close account ----------------------------------------------------------

func (w *world) closesAccount(ctx context.Context, label, which string) error {
	p, err := w.signedIn(ctx, label)
	if err != nil {
		return err
	}
	return w.call(ctx, p, http.MethodPost, "/v1/me/close", map[string]string{"password": w.password(p, which)})
}

func (w *world) triedWrongPassword(ctx context.Context, label string, n int) error {
	for i := 0; i < n; i++ {
		if err := w.closesAccount(ctx, label, "a wrong"); err != nil {
			return err
		}
		if w.last.status != http.StatusForbidden {
			return w.unexpected("a wrong password to be refused (403)")
		}
	}
	return nil
}

func (w *world) canNoLongerSignIn(ctx context.Context, label string) error {
	if err := w.signsIn(ctx, label); err != nil {
		return err
	}
	if w.last.status != http.StatusUnauthorized {
		return w.unexpected(fmt.Sprintf("%q to be refused (401)", label))
	}
	return nil
}

// soleAdminAlone checks one named team in the last 409: alone means the
// caregiver is the only one on it, so the app asks for it to be closed first.
func (w *world) soleAdminAlone(team string, alone bool) error {
	got, err := decodeLast[struct {
		Teams []struct {
			TeamID string `json:"team_id"`
			Alone  bool   `json:"alone"`
		} `json:"teams"`
	}](w)
	if err != nil {
		return err
	}
	id, err := w.teamID(team)
	if err != nil {
		return err
	}
	for _, t := range got.Teams {
		if t.TeamID == id {
			if t.Alone != alone {
				return w.unexpected(fmt.Sprintf("%q with alone=%v", team, alone))
			}
			return nil
		}
	}
	return w.unexpected(fmt.Sprintf("%q named in the 409", team))
}

func (w *world) soleAdminNames(list string) error {
	if w.last.status != http.StatusConflict {
		return w.unexpected("409")
	}
	got, err := decodeLast[struct {
		Message string `json:"message"`
		Teams   []struct {
			TeamID string `json:"team_id"`
			Name   string `json:"name"`
		} `json:"teams"`
	}](w)
	if err != nil {
		return err
	}
	var want, have []string
	for _, n := range names(list) {
		id, err := w.teamID(n)
		if err != nil {
			return err
		}
		want = append(want, id+" "+w.teamName(n))
	}
	for _, t := range got.Teams {
		have = append(have, t.TeamID+" "+t.Name)
	}
	if strings.Join(want, "|") != strings.Join(have, "|") || !strings.Contains(got.Message, "promote someone") {
		return w.unexpected(fmt.Sprintf("409 naming %q and asking to promote someone first", want))
	}
	return nil
}

// ---- send feedback ----------------------------------------------------------

var feedbackKinds = map[string]string{"a bug report": "bug", "a suggestion": "suggestion", "feedback": "other"}
var feedbackKindLines = map[string]string{"a bug report": "Kind: Bug", "a suggestion": "Kind: Suggestion", "feedback": "Kind: Other"}

const (
	featureAppVersion = "1.4.0 (212)"
	featureDevice     = "iPhone 15, iOS 26.1"
)

func (w *world) sendsFeedback(ctx context.Context, label, kind, message, anonymously string) error {
	p, err := w.signedIn(ctx, label)
	if err != nil {
		return err
	}
	if anonymously != "" {
		// The app sends an anonymous report without a token.
		p = nil
	}
	return w.call(ctx, p, http.MethodPost, "/v1/feedback", map[string]string{
		"kind": feedbackKinds[kind], "message": message, "app_version": featureAppVersion, "device": featureDevice,
	})
}

func (w *world) sendsEmptyFeedback(ctx context.Context, label string) error {
	p, err := w.signedIn(ctx, label)
	if err != nil {
		return err
	}
	return w.call(ctx, p, http.MethodPost, "/v1/feedback", map[string]string{
		"kind": "bug", "message": " ", "app_version": featureAppVersion, "device": featureDevice,
	})
}

func (w *world) sentFeedback() (string, error) {
	d, err := w.inProcessOnly()
	if err != nil {
		return "", err
	}
	m, ok := d.feedback.last()
	if !ok {
		return "", fmt.Errorf("no feedback was sent")
	}
	return m.Subject + "\n" + m.Body, nil
}

func (w *world) supportReceives(message, kind string) error {
	sent, err := w.sentFeedback()
	if err != nil {
		return err
	}
	if !strings.Contains(sent, message) || !strings.Contains(sent, feedbackKindLines[kind]) {
		return fmt.Errorf("expected %s reading %q, but what was sent was:\n%s", kind, message, sent)
	}
	return nil
}

func (w *world) feedbackGoesWith(ctx context.Context, label string) error {
	sent, err := w.sentFeedback()
	if err != nil {
		return err
	}
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	if !strings.Contains(sent, fmt.Sprintf("From: %s <%s>", p.label, p.email)) {
		return fmt.Errorf("expected the feedback to go with %q's name and address, but it was:\n%s", label, sent)
	}
	return nil
}

func (w *world) feedbackIdentifiesNobody(ctx context.Context, label string) error {
	sent, err := w.sentFeedback()
	if err != nil {
		return err
	}
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	for _, leak := range []string{p.label, p.email, p.userID} {
		if strings.Contains(sent, leak) {
			return fmt.Errorf("anonymous feedback carries %q:\n%s", leak, sent)
		}
	}
	if !strings.Contains(sent, "From: anonymous") {
		return fmt.Errorf("expected the feedback to say it is anonymous:\n%s", sent)
	}
	return nil
}

func (w *world) feedbackHasVersionAndDevice() error {
	sent, err := w.sentFeedback()
	if err != nil {
		return err
	}
	if !strings.Contains(sent, featureAppVersion) || !strings.Contains(sent, featureDevice) {
		return fmt.Errorf("expected the version and device to go with it:\n%s", sent)
	}
	return nil
}
