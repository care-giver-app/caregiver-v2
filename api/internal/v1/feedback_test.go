package v1

import (
	"bytes"
	"context"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/logger"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store/dynamotest"
)

type fakeSender struct {
	sent []FeedbackMessage
	err  error
}

func (f *fakeSender) Send(_ context.Context, m FeedbackMessage) error {
	if f.err != nil {
		return f.err
	}
	f.sent = append(f.sent, m)
	return nil
}

const okFeedback = `{"kind":"bug","message":"The chart is blank.","app_version":"1.4.0 (212)","device":"iPhone 15, iOS 26.1"}`

func TestFeedback_validation(t *testing.T) {
	sender := &fakeSender{}
	h := NewFeedback(sender)
	for name, body := range map[string]string{
		"not json":         `{`,
		"no kind":          `{"message":"m","app_version":"1","device":"d"}`,
		"unknown kind":     `{"kind":"rant","message":"m","app_version":"1","device":"d"}`,
		"blank message":    `{"kind":"bug","message":"  ","app_version":"1","device":"d"}`,
		"long message":     `{"kind":"bug","message":"` + strings.Repeat("a", 5001) + `","app_version":"1","device":"d"}`,
		"no app_version":   `{"kind":"bug","message":"m","device":"d"}`,
		"no device":        `{"kind":"bug","message":"m","app_version":"1"}`,
		"long app_version": `{"kind":"bug","message":"m","app_version":"` + strings.Repeat("1", 51) + `","device":"d"}`,
		"long device":      `{"kind":"bug","message":"m","app_version":"1","device":"` + strings.Repeat("d", 101) + `"}`,
	} {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, jsonRequest(http.MethodPost, "/v1/feedback", body))
		if rec.Code != http.StatusBadRequest {
			t.Errorf("%s: code=%d", name, rec.Code)
		}
	}
	if len(sender.sent) != 0 {
		t.Fatalf("nothing invalid may be sent: %+v", sender.sent)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, jsonRequest(http.MethodPost, "/v1/feedback",
		`{"kind":"other","message":"`+strings.Repeat("é", 5000)+`","app_version":"","device":""}`))
	if rec.Code != http.StatusAccepted {
		t.Fatalf("at the limits: %d %s", rec.Code, rec.Body.String())
	}
}

func TestFeedback_signedInGoesWithNameAndAddress(t *testing.T) {
	sender := &fakeSender{}
	h := NewFeedback(sender)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, asCaller(jsonRequest(http.MethodPost, "/v1/feedback", okFeedback), "u1", "sam@x.com", "Sam Lee"))
	if rec.Code != http.StatusAccepted || len(sender.sent) != 1 {
		t.Fatalf("code=%d sent=%v", rec.Code, sender.sent)
	}
	m := sender.sent[0]
	if m.Subject != "Feedback: Bug - app 1.4.0 (212)" {
		t.Fatalf("subject = %q", m.Subject)
	}
	for _, want := range []string{"Kind: Bug", "From: Sam Lee <sam@x.com>", "App version: 1.4.0 (212)", "Device: iPhone 15, iOS 26.1", "The chart is blank."} {
		if !strings.Contains(m.Body, want) {
			t.Errorf("body lacks %q:\n%s", want, m.Body)
		}
	}
	if strings.Contains(m.Body, "u1") {
		t.Errorf("the user id has no place in the message:\n%s", m.Body)
	}
}

func TestFeedback_failureIsA500WithoutTheMessage(t *testing.T) {
	var logs bytes.Buffer
	h := NewFeedback(&fakeSender{err: errors.New("sns: throttled")})
	r := jsonRequest(http.MethodPost, "/v1/feedback", okFeedback)
	r = r.WithContext(logger.NewContext(r.Context(), logger.NewWithWriter(&logs, "api", "test", slog.LevelDebug)))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, r)
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("code=%d", rec.Code)
	}
	if strings.Contains(logs.String(), "chart is blank") {
		t.Fatalf("the message was logged: %s", logs.String())
	}
}

// Anonymous means nothing identifying goes with the message or is logged with
// it — even when the caller is, in fact, signed in on the device. The app
// sends an anonymous report without a token, so this is the path it takes.
func TestFeedback_anonymousThroughWrapOptional(t *testing.T) {
	s := dynamotest.Start(t)
	seedUser(t, s, domain.User{UserID: "sub-1", Email: "sam@x.com", Name: "Sam Lee"})
	sender := &fakeSender{}
	a := NewAuthenticator(s)
	a.now = func() time.Time { return time.Now() }

	run := func(withToken bool) (*httptest.ResponseRecorder, string) {
		var logs bytes.Buffer
		log := logger.NewWithWriter(&logs, "api", "test", slog.LevelDebug)
		a.extract = func(r *http.Request) (claims, bool) {
			if r.Header.Get("Authorization") == "" {
				return claims{}, false
			}
			return claims{Sub: "sub-1", Email: "sam@x.com", Name: "Sam Lee", EmailVerified: "true"}, true
		}
		r := jsonRequest(http.MethodPost, "/v1/feedback", okFeedback)
		if withToken {
			r.Header.Set("Authorization", "Bearer t")
		}
		r = r.WithContext(logger.NewContext(r.Context(), log))
		// A handler that logs, as anything downstream might.
		next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			logger.FromContext(r.Context()).Info("sending feedback")
			NewFeedback(sender).ServeHTTP(w, r)
		})
		rec := httptest.NewRecorder()
		a.WrapOptional(next).ServeHTTP(rec, r)
		return rec, logs.String()
	}

	rec, logs := run(false)
	if rec.Code != http.StatusAccepted || len(sender.sent) != 1 {
		t.Fatalf("anonymous: code=%d sent=%d", rec.Code, len(sender.sent))
	}
	m := sender.sent[0]
	for _, leak := range []string{"Sam", "sam@x.com", "sub-1"} {
		if strings.Contains(m.Subject+m.Body, leak) || strings.Contains(logs, leak) {
			t.Errorf("anonymous feedback carries %q:\nmessage: %s\nlogs: %s", leak, m.Body, logs)
		}
	}
	if !strings.Contains(m.Body, "From: anonymous") || !strings.Contains(m.Body, "iPhone 15, iOS 26.1") {
		t.Errorf("body:\n%s", m.Body)
	}

	rec, _ = run(true)
	if rec.Code != http.StatusAccepted || !strings.Contains(sender.sent[1].Body, "From: Sam Lee <sam@x.com>") {
		t.Fatalf("signed in: code=%d body=%s", rec.Code, sender.sent[1].Body)
	}

	// A token that is there but does not verify is refused, not anonymous.
	a.extract = func(*http.Request) (claims, bool) { return claims{}, false }
	r := jsonRequest(http.MethodPost, "/v1/feedback", okFeedback)
	r.Header.Set("Authorization", "Bearer forged")
	rec = httptest.NewRecorder()
	a.WrapOptional(NewFeedback(sender)).ServeHTTP(rec, r)
	if rec.Code != http.StatusUnauthorized || len(sender.sent) != 2 {
		t.Fatalf("bad token: code=%d sent=%d", rec.Code, len(sender.sent))
	}
}

func TestFeedbackSubjectAndOneLine(t *testing.T) {
	// Only printable ASCII survives: an SNS subject allows nothing else.
	if got := feedbackSubject("Bug", "1.0 é\n(2)"); got != "Feedback: Bug - app 1.0 (2)" {
		t.Fatalf("subject = %q", got)
	}
	if got := feedbackSubject("Suggestion", strings.Repeat("9", 200)); len(got) != 100 {
		t.Fatalf("subject length = %d", len(got))
	}
	if got := feedbackSubject("Other", ""); got != "Feedback: Other" {
		t.Fatalf("subject = %q", got)
	}
	if got := oneLine("  iPhone\n15\r\nFrom: forged "); got != "iPhone 15 From: forged" {
		t.Fatalf("oneLine = %q", got)
	}
}
