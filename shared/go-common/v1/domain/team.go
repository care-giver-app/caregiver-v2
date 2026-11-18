package domain

import (
	"crypto/rand"
	"encoding/base64"
	"errors"
	"net/mail"
	"strings"
	"time"
	"unicode/utf8"
)

// InvitationTTL is how long an invitation stays redeemable: two weeks, per
// the PRD's Invitation.
const InvitationTTL = 14 * 24 * time.Hour

// NewInviteCode returns a URL-safe, 128-bit random invite code. The PRD wants
// it long and random rather than short enough to read aloud, because it is
// always copied.
func NewInviteCode() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

// MaxEmailLength is the longest address an invitation takes.
const MaxEmailLength = 254

// ErrInvalidEmail is returned by ValidateInviteEmail.
var ErrInvalidEmail = errors.New("a valid email address is required")

// ValidateInviteEmail normalizes the address and requires a bare one (no
// display name) of at most MaxEmailLength characters.
func ValidateInviteEmail(s string) (string, error) {
	email := NormalizeEmail(s)
	if email == "" || len(email) > MaxEmailLength {
		return "", ErrInvalidEmail
	}
	a, err := mail.ParseAddress(email)
	if err != nil || a.Address != email {
		return "", ErrInvalidEmail
	}
	return email, nil
}

// MaxReceiverNameLength is the longest care receiver name, in characters.
const MaxReceiverNameLength = 100

// ErrInvalidReceiverName is returned by ValidateReceiverName.
var ErrInvalidReceiverName = errors.New("name must be 1-100 characters")

// ValidateReceiverName trims surrounding whitespace and requires 1–100
// characters. It returns the trimmed name.
func ValidateReceiverName(s string) (string, error) {
	name := strings.TrimSpace(s)
	if n := utf8.RuneCountInString(name); n < 1 || n > MaxReceiverNameLength {
		return "", ErrInvalidReceiverName
	}
	return name, nil
}

// ErrInvalidTimeZone is returned by ValidateTimeZone.
var ErrInvalidTimeZone = errors.New("time_zone must be an IANA time zone")

// ValidateTimeZone requires an IANA zone name the runtime knows. "Local" is
// refused, since it means wherever the server runs, and so is the empty
// string, which time.LoadLocation reads as UTC.
func ValidateTimeZone(s string) (string, error) {
	tz := strings.TrimSpace(s)
	if tz == "" || tz == "Local" {
		return "", ErrInvalidTimeZone
	}
	if _, err := time.LoadLocation(tz); err != nil {
		return "", ErrInvalidTimeZone
	}
	return tz, nil
}

// EmergencyContact is one row of a care receiver's emergency contacts.
type EmergencyContact struct {
	ContactID    string `dynamodbav:"contact_id"`
	Name         string `dynamodbav:"name"`
	Relationship string `dynamodbav:"relationship"`
	Phone        string `dynamodbav:"phone"`
}

// CareInstructions is one receiver's written instructions and emergency
// contacts. UpdatedBy and UpdatedAt stamp the body alone (ADR 0012, amended in
// the Team endpoints gate): editing contacts leaves them as they are. Body,
// UpdatedBy and UpdatedAt are absent while no instructions are written.
type CareInstructions struct {
	ReceiverID string             `dynamodbav:"receiver_id"`
	TeamID     string             `dynamodbav:"team_id"`
	Body       string             `dynamodbav:"body,omitempty"`
	Contacts   []EmergencyContact `dynamodbav:"contacts,omitempty"`
	UpdatedBy  string             `dynamodbav:"updated_by,omitempty"`
	UpdatedAt  *time.Time         `dynamodbav:"updated_at,omitempty"`
}

// MaxCareInstructionsLength is the longest body, in characters.
const MaxCareInstructionsLength = 20000

// ErrCareInstructionsTooLong is returned by ValidateCareInstructions.
var ErrCareInstructionsTooLong = errors.New("care instructions must be at most 20000 characters")

// ValidateCareInstructions checks the body's length and returns the body to
// store: as written, or "" when it holds nothing but whitespace, which clears
// the instructions.
func ValidateCareInstructions(body string) (string, error) {
	if utf8.RuneCountInString(body) > MaxCareInstructionsLength {
		return "", ErrCareInstructionsTooLong
	}
	if strings.TrimSpace(body) == "" {
		return "", nil
	}
	return body, nil
}

// Emergency contact limits, per the EmergencyContactWrite schema.
const (
	MaxEmergencyContacts  = 20
	MaxContactNameLength  = 100
	MaxRelationshipLength = 100
	MaxContactPhoneLength = 40
	contactsErrPrefix     = "emergency contacts: "
)

// ContactWrite is one contact as an admin sends it. ContactID is empty for a
// new contact.
type ContactWrite struct {
	ContactID    string
	Name         string
	Relationship string
	Phone        string
}

// ErrUnknownContact is returned by ResolveContacts for a contact_id the
// receiver does not have.
var ErrUnknownContact = errors.New(contactsErrPrefix + "a contact_id is not one of this receiver's contacts")

// ResolveContacts validates the whole list an admin sends and returns it as
// stored, in the order sent: each field trimmed, a contact sent with its
// contact_id keeping it, a new one given newID(). A contact_id the receiver
// does not have, or one sent twice, is refused.
func ResolveContacts(in []ContactWrite, existing []EmergencyContact, newID func() string) ([]EmergencyContact, error) {
	if len(in) > MaxEmergencyContacts {
		return nil, errors.New(contactsErrPrefix + "at most 20")
	}
	known := make(map[string]bool, len(existing))
	for _, c := range existing {
		known[c.ContactID] = true
	}
	seen := map[string]bool{}
	out := make([]EmergencyContact, 0, len(in))
	for _, c := range in {
		name := strings.TrimSpace(c.Name)
		rel := strings.TrimSpace(c.Relationship)
		phone := strings.TrimSpace(c.Phone)
		if n := utf8.RuneCountInString(name); n < 1 || n > MaxContactNameLength {
			return nil, errors.New(contactsErrPrefix + "name must be 1-100 characters")
		}
		if utf8.RuneCountInString(rel) > MaxRelationshipLength {
			return nil, errors.New(contactsErrPrefix + "relationship must be at most 100 characters")
		}
		if n := utf8.RuneCountInString(phone); n < 1 || n > MaxContactPhoneLength {
			return nil, errors.New(contactsErrPrefix + "phone must be 1-40 characters")
		}
		id := c.ContactID
		if id == "" {
			id = newID()
		} else if !known[id] {
			return nil, ErrUnknownContact
		}
		if seen[id] {
			return nil, errors.New(contactsErrPrefix + "a contact_id is sent twice")
		}
		seen[id] = true
		out = append(out, EmergencyContact{ContactID: id, Name: name, Relationship: rel, Phone: phone})
	}
	return out, nil
}
