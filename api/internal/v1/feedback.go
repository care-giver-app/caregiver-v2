package v1

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"unicode/utf8"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/sns"

	"github.com/care-giver-app/caregiver-v2/api/internal/httpx"
)

// FeedbackMessage is one piece of feedback, ready to send.
type FeedbackMessage struct {
	Subject string
	Body    string
}

// FeedbackSender delivers feedback to the people behind the app. Nothing is
// kept: feedback is a message, not a record.
type FeedbackSender interface {
	Send(ctx context.Context, m FeedbackMessage) error
}

// snsSender publishes feedback to a topic whose subscriber is the support
// address.
type snsSender struct {
	client   *sns.Client
	topicARN string
}

func NewSNSFeedbackSender(client *sns.Client, topicARN string) FeedbackSender {
	return &snsSender{client: client, topicARN: topicARN}
}

func (s *snsSender) Send(ctx context.Context, m FeedbackMessage) error {
	_, err := s.client.Publish(ctx, &sns.PublishInput{
		TopicArn: aws.String(s.topicARN),
		Subject:  aws.String(m.Subject),
		Message:  aws.String(m.Body),
	})
	return err
}

// Feedback serves POST /v1/feedback. It is mounted with
// Authenticator.WrapOptional: with a token the caller is known and the
// message goes with their name and address so a reply can come by email;
// without one there is no caller, nothing identifying is added to the
// request's logger, and nothing identifying goes with the message.
type Feedback struct{ sender FeedbackSender }

func NewFeedback(sender FeedbackSender) *Feedback { return &Feedback{sender: sender} }

// Limits from FeedbackRequest.
const (
	maxFeedbackMessage = 5000
	maxAppVersion      = 50
	maxDevice          = 100
)

var feedbackKinds = map[string]string{"bug": "Bug", "suggestion": "Suggestion", "other": "Other"}

func (h *Feedback) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Kind       string  `json:"kind"`
		Message    string  `json:"message"`
		AppVersion *string `json:"app_version"`
		Device     *string `json:"device"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid body")
		return
	}
	kind, ok := feedbackKinds[req.Kind]
	if !ok {
		httpx.WriteError(w, http.StatusBadRequest, "kind must be bug, suggestion or other")
		return
	}
	message := strings.TrimSpace(req.Message)
	if n := utf8.RuneCountInString(message); n < 1 || n > maxFeedbackMessage {
		httpx.WriteError(w, http.StatusBadRequest, "message must be 1-5000 characters")
		return
	}
	if req.AppVersion == nil || req.Device == nil {
		httpx.WriteError(w, http.StatusBadRequest, "app_version and device are required")
		return
	}
	appVersion, device := oneLine(*req.AppVersion), oneLine(*req.Device)
	if utf8.RuneCountInString(appVersion) > maxAppVersion || utf8.RuneCountInString(device) > maxDevice {
		httpx.WriteError(w, http.StatusBadRequest, "app_version is at most 50 characters and device at most 100")
		return
	}

	from := "anonymous"
	if c := callerFrom(r.Context()); c != nil {
		name := c.Name
		if name == "" {
			name = "(no name)"
		}
		from = fmt.Sprintf("%s <%s>", oneLine(name), c.Email)
	}
	m := FeedbackMessage{
		Subject: feedbackSubject(kind, appVersion),
		Body: fmt.Sprintf("Kind: %s\nFrom: %s\nApp version: %s\nDevice: %s\n\n%s\n",
			kind, from, appVersion, device, message),
	}
	if err := h.sender.Send(r.Context(), m); err != nil {
		// The error names the topic, never the message or the sender.
		httpx.ServerError(w, r, err, "feedback could not be sent")
		return
	}
	w.WriteHeader(http.StatusAccepted)
}

// feedbackSubject is an SNS subject: printable ASCII on one line, at most 100
// characters.
func feedbackSubject(kind, appVersion string) string {
	s := "Feedback: " + kind
	if appVersion != "" {
		s += " - app " + appVersion
	}
	b := make([]byte, 0, len(s))
	for i := 0; i < len(s) && len(b) < 100; i++ {
		if c := s[i]; c >= 0x20 && c < 0x7f {
			b = append(b, c)
		}
	}
	return string(b)
}

// oneLine trims s and folds any line breaks into spaces, so a field cannot
// forge another line of the message.
func oneLine(s string) string {
	return strings.Join(strings.Fields(s), " ")
}
