package features_test

import (
	"context"
	"fmt"
	"sync"

	v1 "github.com/care-giver-app/caregiver-v2/api/internal/v1"
)

// fakeIdentity stands in for the Cognito user pool in-process: each person's
// password, the address waiting on a code, and the lockout after too many
// wrong passwords. lockAfter matches Cognito's own: the sixth wrong try in a
// row is refused as too many.
type fakeIdentity struct {
	mu        sync.Mutex
	byEmail   map[string]string // sign-in address → user id
	passwords map[string]string // user id → password
	wrong     map[string]int    // user id → wrong passwords in a row
	pending   map[string]string // user id → the address the code was sent to
	deleted   map[string]bool
}

const lockAfter = 5

func newFakeIdentity() *fakeIdentity {
	return &fakeIdentity{
		byEmail: map[string]string{}, passwords: map[string]string{}, wrong: map[string]int{},
		pending: map[string]string{}, deleted: map[string]bool{},
	}
}

func (f *fakeIdentity) add(p *person) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.byEmail[p.email] = p.userID
	f.passwords[p.userID] = p.password
}

func (f *fakeIdentity) CheckPassword(_ context.Context, signIn, password string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	id, ok := f.byEmail[signIn]
	if !ok || f.deleted[id] {
		return v1.ErrWrongPassword
	}
	if f.wrong[id] >= lockAfter {
		return v1.ErrTooManyAttempts
	}
	if f.passwords[id] != password {
		f.wrong[id]++
		return v1.ErrWrongPassword
	}
	f.wrong[id] = 0
	return nil
}

func (f *fakeIdentity) StartEmailChange(_ context.Context, userID, email string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if other, ok := f.byEmail[email]; ok && other != userID && !f.deleted[other] {
		return v1.ErrEmailInUse
	}
	f.pending[userID] = email
	return nil
}

func (f *fakeIdentity) DeleteUser(_ context.Context, userID string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.deleted[userID] = true
	return nil
}

// confirm is the caregiver entering the code: the waiting address becomes
// the one they sign in with, and the tokens they get from now on carry it.
func (f *fakeIdentity) confirm(p *person) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	email, ok := f.pending[p.userID]
	if !ok {
		return fmt.Errorf("no code was sent for %q", p.label)
	}
	delete(f.pending, p.userID)
	delete(f.byEmail, p.email)
	f.byEmail[email] = p.userID
	p.email = email
	return nil
}

// fakeFeedback keeps what was sent, so a scenario can read it.
type fakeFeedback struct {
	mu   sync.Mutex
	sent []v1.FeedbackMessage
}

func (f *fakeFeedback) Send(_ context.Context, m v1.FeedbackMessage) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.sent = append(f.sent, m)
	return nil
}

func (f *fakeFeedback) last() (v1.FeedbackMessage, bool) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if len(f.sent) == 0 {
		return v1.FeedbackMessage{}, false
	}
	return f.sent[len(f.sent)-1], true
}
