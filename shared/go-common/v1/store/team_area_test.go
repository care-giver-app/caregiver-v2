package store_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/store/dynamotest"
)

func TestReceiver_CreateChangeAndStatus(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	s := l.Stores
	now := time.Date(2026, 11, 16, 12, 0, 0, 0, time.UTC)

	rc := domain.Receiver{ReceiverID: "r1", TeamID: "t1", Name: "Grandma", TimeZone: "America/Chicago",
		Status: domain.ReceiverActive, CreatedBy: "a", CreatedAt: now}
	if err := s.Receivers.Create(ctx, rc); err != nil {
		t.Fatal(err)
	}
	if err := s.Receivers.Create(ctx, rc); err == nil {
		t.Fatal("duplicate create should fail")
	}

	got, err := s.Receivers.Change(ctx, "r1", "Nana", "America/New_York")
	if err != nil || got.Name != "Nana" || got.TimeZone != "America/New_York" || got.CreatedBy != "a" {
		t.Fatalf("change: %+v %v", got, err)
	}
	if _, err := s.Receivers.Change(ctx, "missing", "x", "UTC"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("change missing: %v", err)
	}

	arch, err := s.Receivers.SetStatus(ctx, "r1", domain.ReceiverArchived, "a", now)
	if err != nil || arch.Status != domain.ReceiverArchived || arch.ArchivedBy != "a" || !arch.ArchivedAt.Equal(now) {
		t.Fatalf("archive: %+v %v", arch, err)
	}
	// A repeat keeps the original stamp.
	again, err := s.Receivers.SetStatus(ctx, "r1", domain.ReceiverArchived, "b", now.Add(time.Hour))
	if err != nil || again.ArchivedBy != "a" || !again.ArchivedAt.Equal(now) {
		t.Fatalf("archive again: %+v %v", again, err)
	}
	if _, err := s.Receivers.Change(ctx, "r1", "x", "UTC"); !errors.Is(err, store.ErrReceiverArchived) {
		t.Fatalf("change archived: %v", err)
	}
	if list, err := s.Receivers.ListByTeam(ctx, "t1", domain.ReceiverArchived); err != nil || len(list) != 1 {
		t.Fatalf("archived list: %+v %v", list, err)
	}
	if list, err := s.Receivers.ListActiveByTeam(ctx, "t1"); err != nil || len(list) != 0 {
		t.Fatalf("active list: %+v %v", list, err)
	}

	back, err := s.Receivers.SetStatus(ctx, "r1", domain.ReceiverActive, "a", now)
	if err != nil || back.Status != domain.ReceiverActive || back.ArchivedBy != "" || back.ArchivedAt != nil {
		t.Fatalf("restore: %+v %v", back, err)
	}
	if _, err := s.Receivers.SetStatus(ctx, "missing", domain.ReceiverArchived, "a", now); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("status missing: %v", err)
	}
}

func TestCareInstructions_bodyAndContactsStampSeparately(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	s := l.Stores
	t1 := time.Date(2026, 11, 16, 12, 0, 0, 0, time.UTC)
	rc := domain.Receiver{ReceiverID: "r1", TeamID: "t1", Name: "G", TimeZone: "UTC", Status: domain.ReceiverActive, CreatedAt: t1}
	seed(t, l, l.Names.Receivers, rc)

	if _, err := s.CareInstructions.Get(ctx, "r1"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("none yet: %v", err)
	}
	if err := s.SetCareInstructionsBody(ctx, rc, "Pills at 8.", "a", t1); err != nil {
		t.Fatal(err)
	}
	contacts := []domain.EmergencyContact{
		{ContactID: "c1", Name: "Dr Lee", Relationship: "GP", Phone: "555-1"},
		{ContactID: "c2", Name: "Sam", Relationship: "Son", Phone: "555-2"},
	}
	if err := s.SetEmergencyContacts(ctx, rc, contacts); err != nil {
		t.Fatal(err)
	}
	ci, err := s.CareInstructions.Get(ctx, "r1")
	if err != nil || ci.Body != "Pills at 8." || ci.UpdatedBy != "a" || !ci.UpdatedAt.Equal(t1) || ci.TeamID != "t1" ||
		len(ci.Contacts) != 2 || ci.Contacts[0].ContactID != "c1" || ci.Contacts[1].Name != "Sam" {
		t.Fatalf("after contacts: %+v %v", ci, err)
	}

	// Clearing the body removes its stamp and leaves the contacts.
	if err := s.SetCareInstructionsBody(ctx, rc, "", "b", t1.Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	ci, _ = s.CareInstructions.Get(ctx, "r1")
	if ci.Body != "" || ci.UpdatedBy != "" || ci.UpdatedAt != nil || len(ci.Contacts) != 2 {
		t.Fatalf("after clear: %+v", ci)
	}
	if err := s.SetEmergencyContacts(ctx, rc, nil); err != nil {
		t.Fatal(err)
	}
	if ci, _ = s.CareInstructions.Get(ctx, "r1"); len(ci.Contacts) != 0 {
		t.Fatalf("contacts not emptied: %+v", ci)
	}

	archived := rc
	archived.Status = domain.ReceiverArchived
	seed(t, l, l.Names.Receivers, archived)
	if err := s.SetCareInstructionsBody(ctx, rc, "x", "a", t1); !errors.Is(err, store.ErrReceiverArchived) {
		t.Fatalf("archived body: %v", err)
	}
	if err := s.SetEmergencyContacts(ctx, rc, contacts); !errors.Is(err, store.ErrReceiverArchived) {
		t.Fatalf("archived contacts: %v", err)
	}
	if ci, _ = s.CareInstructions.Get(ctx, "r1"); ci.Body != "" || len(ci.Contacts) != 0 {
		t.Fatalf("archived receiver written: %+v", ci)
	}
	gone := domain.Receiver{ReceiverID: "missing", TeamID: "t1"}
	if err := s.SetCareInstructionsBody(ctx, gone, "x", "a", t1); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("missing receiver: %v", err)
	}
}

func TestInvitations_ListPendingByTeam(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	now := time.Date(2026, 11, 16, 12, 0, 0, 0, time.UTC)
	for _, inv := range []domain.Invitation{
		{Code: "p1", TeamID: "t1", Email: "a@x.com", Status: domain.InvitePending},
		{Code: "p2", TeamID: "t1", Email: "b@x.com", Status: domain.InvitePending},
		{Code: "used", TeamID: "t1", Email: "c@x.com", Status: domain.InviteAccepted},
		{Code: "other", TeamID: "t2", Email: "a@x.com", Status: domain.InvitePending},
	} {
		inv.InvitedBy, inv.CreatedAt, inv.ExpiresAt = "a", now, now.Add(time.Hour).Unix()
		if err := l.Stores.Invitations.Create(ctx, inv); err != nil {
			t.Fatal(err)
		}
	}
	got, err := l.Stores.Invitations.ListPendingByTeam(ctx, "t1")
	if err != nil || len(got) != 2 {
		t.Fatalf("list: %+v %v", got, err)
	}
	for _, inv := range got {
		if inv.Code != "p1" && inv.Code != "p2" {
			t.Fatalf("unexpected %+v", inv)
		}
	}
}

func TestEntries_FutureOpenAndRetime(t *testing.T) {
	l := dynamotest.StartLocal(t)
	ctx := context.Background()
	now := time.Date(2026, 11, 16, 12, 0, 0, 0, time.UTC)
	past, future := now.Add(-time.Hour), now.Add(time.Hour)
	for _, e := range []domain.Entry{
		{EntryID: "past", OccurrenceLocal: "2026-11-16T05:00", OccurrenceAt: &past, State: domain.EntryScheduled, TimelineAt: past, OpenAt: &past},
		{EntryID: "future", OccurrenceLocal: "2026-11-16T07:00", OccurrenceAt: &future, State: domain.EntryScheduled, TimelineAt: future, OpenAt: &future},
		{EntryID: "skipped", OccurrenceLocal: "2026-11-16T07:00", OccurrenceAt: &future, State: domain.EntrySkipped, TimelineAt: future},
	} {
		e.TrackerID, e.ReceiverID, e.TeamID, e.ScheduleID, e.Values, e.CreatedAt = "tr1", "r1", "t1", "s1", map[string]any{}, now
		seed(t, l, l.Names.Entries, e)
	}
	got, err := l.Stores.Entries.FutureOpenByReceiver(ctx, "r1", now)
	if err != nil || len(got) != 1 || got[0].EntryID != "future" {
		t.Fatalf("future open: %+v %v", got, err)
	}
	moved := now.Add(2 * time.Hour)
	if ok, err := l.Stores.Entries.Retime(ctx, "future", "2026-11-16T07:00", moved); err != nil || !ok {
		t.Fatalf("retime: %v %v", ok, err)
	}
	e, _ := l.Stores.Entries.Get(ctx, "future")
	if !e.OccurrenceAt.Equal(moved) || !e.TimelineAt.Equal(moved) || !e.OpenAt.Equal(moved) || e.OccurrenceLocal != "2026-11-16T07:00" {
		t.Fatalf("retimed: %+v", e)
	}
	// Not scheduled, or for another local time: left alone.
	if ok, err := l.Stores.Entries.Retime(ctx, "skipped", "2026-11-16T07:00", moved); err != nil || ok {
		t.Fatalf("skipped retimed: %v %v", ok, err)
	}
	if ok, err := l.Stores.Entries.Retime(ctx, "future", "2026-11-16T09:00", now); err != nil || ok {
		t.Fatalf("wrong local retimed: %v %v", ok, err)
	}
}
