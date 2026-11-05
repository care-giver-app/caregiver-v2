// Package domain holds the v1 entity types (docs/adr/0012-target-data-model.md)
// and pure helpers. No AWS imports. It sits beside the old domain package until
// cutover, when the old one is deleted.
package domain

import (
	"errors"
	"strings"
	"time"
	"unicode/utf8"
)

type Role string

const (
	RoleAdmin     Role = "admin"
	RoleCaregiver Role = "caregiver"
)

func (r Role) Valid() bool { return r == RoleAdmin || r == RoleCaregiver }

type UserStatus string

const (
	UserActive UserStatus = "active"
	UserClosed UserStatus = "closed"
)

// User is keyed by the Cognito sub. Closing an account removes email and name,
// so email is omitempty: an empty string may not be written to the email-index
// key, and a closed row must drop out of that index.
type User struct {
	UserID             string     `dynamodbav:"user_id"`
	Email              string     `dynamodbav:"email,omitempty"`
	Name               string     `dynamodbav:"name"`
	EmailNotifications bool       `dynamodbav:"email_notifications"`
	Status             UserStatus `dynamodbav:"status"`
	ClosedAt           *time.Time `dynamodbav:"closed_at,omitempty"`
	CreatedAt          time.Time  `dynamodbav:"created_at"`
}

type TeamStatus string

const (
	TeamActive   TeamStatus = "active"
	TeamArchived TeamStatus = "archived"
)

// Team replaces CareGroup. "Close this care team" archives it.
type Team struct {
	TeamID     string     `dynamodbav:"team_id"`
	Name       string     `dynamodbav:"name"`
	Status     TeamStatus `dynamodbav:"status"`
	ArchivedBy string     `dynamodbav:"archived_by,omitempty"`
	ArchivedAt *time.Time `dynamodbav:"archived_at,omitempty"`
	CreatedBy  string     `dynamodbav:"created_by"`
	CreatedAt  time.Time  `dynamodbav:"created_at"`
}

// MaxTeamNameLength is the longest team name, in characters (runes).
const MaxTeamNameLength = 100

// ErrInvalidTeamName is returned by ValidateTeamName.
var ErrInvalidTeamName = errors.New("team name must be 1-100 characters")

// ValidateTeamName trims surrounding whitespace and requires 1–100 characters.
// It returns the trimmed name.
func ValidateTeamName(s string) (string, error) {
	name := strings.TrimSpace(s)
	if n := utf8.RuneCountInString(name); n < 1 || n > MaxTeamNameLength {
		return "", ErrInvalidTeamName
	}
	return name, nil
}

// Membership is one caregiver on one team, with that caregiver's own choice of
// which kinds of notification the team sends them.
type Membership struct {
	UserID                 string    `dynamodbav:"user_id"`
	TeamID                 string    `dynamodbav:"team_id"`
	Role                   Role      `dynamodbav:"role"`
	JoinedAt               time.Time `dynamodbav:"joined_at"`
	NotifyReminders        bool      `dynamodbav:"notify_reminders"`
	NotifyRangeAlerts      bool      `dynamodbav:"notify_range_alerts"`
	NotifyGapAlerts        bool      `dynamodbav:"notify_gap_alerts"`
	NotifyUnrecordedAlerts bool      `dynamodbav:"notify_unrecorded_alerts"`
}

// NewMembership builds a membership joined at now with every notification
// kind on, which is the default the ADR requires.
func NewMembership(userID, teamID string, role Role, now time.Time) Membership {
	return Membership{
		UserID:                 userID,
		TeamID:                 teamID,
		Role:                   role,
		JoinedAt:               now,
		NotifyReminders:        true,
		NotifyRangeAlerts:      true,
		NotifyGapAlerts:        true,
		NotifyUnrecordedAlerts: true,
	}
}

type InvitationStatus string

const (
	InvitePending  InvitationStatus = "pending"
	InviteAccepted InvitationStatus = "accepted"
	InviteRevoked  InvitationStatus = "revoked"
)

// Invitation has no role: every invitation joins as a caregiver.
type Invitation struct {
	Code      string           `dynamodbav:"code"`
	TeamID    string           `dynamodbav:"team_id"`
	Email     string           `dynamodbav:"email"`
	Status    InvitationStatus `dynamodbav:"status"`
	InvitedBy string           `dynamodbav:"invited_by"`
	CreatedAt time.Time        `dynamodbav:"created_at"`
	ExpiresAt int64            `dynamodbav:"expires_at"` // unix seconds; DynamoDB TTL attribute
}

// Expired reports whether the invitation is at or past its expiry.
func (i Invitation) Expired(now time.Time) bool { return now.Unix() >= i.ExpiresAt }

// NormalizeEmail lowercases and trims for consistent matching.
func NormalizeEmail(email string) string { return strings.ToLower(strings.TrimSpace(email)) }
