// Package domain holds the B1 entity types and pure helpers. No AWS imports.
package domain

import (
	"crypto/rand"
	"encoding/base64"
	"strings"
	"time"
)

type Role string

const (
	RoleAdmin     Role = "admin"
	RoleCaregiver Role = "caregiver"
)

func (r Role) Valid() bool { return r == RoleAdmin || r == RoleCaregiver }

type User struct {
	UserID    string    `dynamodbav:"user_id"`
	Email     string    `dynamodbav:"email"`
	Name      string    `dynamodbav:"name"`
	CreatedAt time.Time `dynamodbav:"created_at"`
}

type CareGroup struct {
	CareGroupID string    `dynamodbav:"care_group_id"`
	Name        string    `dynamodbav:"name"`
	CreatedBy   string    `dynamodbav:"created_by"`
	CreatedAt   time.Time `dynamodbav:"created_at"`
}

type Membership struct {
	UserID      string    `dynamodbav:"user_id"`
	CareGroupID string    `dynamodbav:"care_group_id"`
	Role        Role      `dynamodbav:"role"`
	CreatedAt   time.Time `dynamodbav:"created_at"`
}

type InvitationStatus string

const (
	InvitePending  InvitationStatus = "pending"
	InviteAccepted InvitationStatus = "accepted"
	InviteRevoked  InvitationStatus = "revoked"
)

type Invitation struct {
	Token       string           `dynamodbav:"token"`
	CareGroupID string           `dynamodbav:"care_group_id"`
	Email       string           `dynamodbav:"email"`
	Role        Role             `dynamodbav:"role"`
	Status      InvitationStatus `dynamodbav:"status"`
	InvitedBy   string           `dynamodbav:"invited_by"`
	CreatedAt   time.Time        `dynamodbav:"created_at"`
	ExpiresAt   int64            `dynamodbav:"expires_at"` // unix seconds; DynamoDB TTL attribute
}

// Expired reports whether the invitation is at or past its expiry.
func (i Invitation) Expired(now time.Time) bool { return now.Unix() >= i.ExpiresAt }

// NormalizeEmail lowercases and trims for consistent matching.
func NormalizeEmail(email string) string { return strings.ToLower(strings.TrimSpace(email)) }

// NewInviteToken returns a URL-safe, 128-bit random single-use token.
func NewInviteToken() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}
