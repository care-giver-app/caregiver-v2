package handlers_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/care-giver-app/caregiver-v2/api/internal/handlers"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
	"github.com/care-giver-app/caregiver-v2/shared/go-common/store/dynamotest"
)

func seedScheduledTracker(t *testing.T, h *handlers.ScheduledItems, put func(domain.Tracker), putRcv func(domain.Receiver)) (rcv domain.Receiver, tr domain.Tracker) {
	rcv = domain.Receiver{ReceiverID: "rcv1", CareGroupID: "cg1", Name: "Mom"}
	tr = domain.Tracker{
		TrackerID: "trk1", ReceiverID: "rcv1", CareGroupID: "cg1", Name: "Dentist",
		Kind: domain.KindScheduled,
		Fields: []domain.Field{{Key: "location", Label: "Location", Type: domain.FieldText}},
	}
	putRcv(rcv)
	put(tr)
	return rcv, tr
}

func TestScheduledItems_CreateHappyPath(t *testing.T) {
	s := dynamotest.Start(t)
	h := handlers.NewScheduledItems(s)
	_, _ = seedScheduledTracker(t, h,
		func(tr domain.Tracker) { _ = s.Trackers.Put(context.Background(), tr) },
		func(r domain.Receiver) { _ = s.Receivers.Put(context.Background(), r) })

	body := `{"scheduled_for":"2026-08-01T10:00:00Z","values":{"location":"5th St Dental"},"note":"cleaning"}`
	req := httptest.NewRequest(http.MethodPost, "/trackers/trk1/scheduled-items", strings.NewReader(body))
	req.SetPathValue("trackerId", "trk1")
	req = withAuth(req, "u1", "u1@x.com", map[string]domain.Role{"cg1": domain.RoleCaregiver})
	rec := httptest.NewRecorder()
	h.Create(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("want 201, got %d: %s", rec.Code, rec.Body.String())
	}
	var got domain.ScheduledItem
	_ = json.Unmarshal(rec.Body.Bytes(), &got)
	if got.CareGroupID != "cg1" || got.ReceiverID != "rcv1" || got.TrackerID != "trk1" {
		t.Fatalf("denormalized ids wrong: %+v", got)
	}
	if got.Values["location"] != "5th St Dental" {
		t.Fatalf("values not persisted: %+v", got.Values)
	}
}

func TestScheduledItems_CreateRejectsNonScheduledTracker(t *testing.T) {
	s := dynamotest.Start(t)
	h := handlers.NewScheduledItems(s)
	_ = s.Receivers.Put(context.Background(), domain.Receiver{ReceiverID: "rcv1", CareGroupID: "cg1", Name: "Mom"})
	_ = s.Trackers.Put(context.Background(), domain.Tracker{TrackerID: "trk2", ReceiverID: "rcv1", CareGroupID: "cg1", Name: "Weight", Kind: domain.KindMeasurement})

	req := httptest.NewRequest(http.MethodPost, "/trackers/trk2/scheduled-items", strings.NewReader(`{"scheduled_for":"2026-08-01T10:00:00Z"}`))
	req.SetPathValue("trackerId", "trk2")
	req = withAuth(req, "u1", "u1@x.com", map[string]domain.Role{"cg1": domain.RoleCaregiver})
	rec := httptest.NewRecorder()
	h.Create(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("want 400, got %d", rec.Code)
	}
}

func TestScheduledItems_CreateRejectsNonMember(t *testing.T) {
	s := dynamotest.Start(t)
	h := handlers.NewScheduledItems(s)
	seedScheduledTracker(t, h,
		func(tr domain.Tracker) { _ = s.Trackers.Put(context.Background(), tr) },
		func(r domain.Receiver) { _ = s.Receivers.Put(context.Background(), r) })

	req := httptest.NewRequest(http.MethodPost, "/trackers/trk1/scheduled-items", strings.NewReader(`{"scheduled_for":"2026-08-01T10:00:00Z"}`))
	req.SetPathValue("trackerId", "trk1")
	req = withAuth(req, "intruder", "x@x.com", map[string]domain.Role{"other": domain.RoleAdmin})
	rec := httptest.NewRecorder()
	h.Create(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("want 403, got %d", rec.Code)
	}
}

func TestScheduledItems_CreateRejectsMissingScheduledFor(t *testing.T) {
	s := dynamotest.Start(t)
	h := handlers.NewScheduledItems(s)
	seedScheduledTracker(t, h,
		func(tr domain.Tracker) { _ = s.Trackers.Put(context.Background(), tr) },
		func(r domain.Receiver) { _ = s.Receivers.Put(context.Background(), r) })

	req := httptest.NewRequest(http.MethodPost, "/trackers/trk1/scheduled-items", strings.NewReader(`{"values":{}}`))
	req.SetPathValue("trackerId", "trk1")
	req = withAuth(req, "u1", "u1@x.com", map[string]domain.Role{"cg1": domain.RoleCaregiver})
	rec := httptest.NewRecorder()
	h.Create(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("want 400, got %d", rec.Code)
	}
}

func TestScheduledItems_ListByReceiverAndItemLifecycle(t *testing.T) {
	s := dynamotest.Start(t)
	h := handlers.NewScheduledItems(s)
	seedScheduledTracker(t, h,
		func(tr domain.Tracker) { _ = s.Trackers.Put(context.Background(), tr) },
		func(r domain.Receiver) { _ = s.Receivers.Put(context.Background(), r) })
	member := func(r *http.Request) *http.Request {
		return withAuth(r, "u1", "u1@x.com", map[string]domain.Role{"cg1": domain.RoleCaregiver})
	}

	// create
	cr := httptest.NewRequest(http.MethodPost, "/trackers/trk1/scheduled-items", strings.NewReader(`{"scheduled_for":"2026-08-01T10:00:00Z","values":{"location":"A"}}`))
	cr.SetPathValue("trackerId", "trk1")
	crRec := httptest.NewRecorder()
	h.Create(crRec, member(cr))
	var created domain.ScheduledItem
	_ = json.Unmarshal(crRec.Body.Bytes(), &created)

	// list by receiver
	lr := httptest.NewRequest(http.MethodGet, "/receivers/rcv1/scheduled-items", nil)
	lr.SetPathValue("receiverId", "rcv1")
	lrRec := httptest.NewRecorder()
	h.ListByReceiver(lrRec, member(lr))
	if lrRec.Code != http.StatusOK || !strings.Contains(lrRec.Body.String(), created.ScheduledItemID) {
		t.Fatalf("list by receiver missing item: %d %s", lrRec.Code, lrRec.Body.String())
	}

	// update (reschedule)
	ur := httptest.NewRequest(http.MethodPut, "/scheduled-items/"+created.ScheduledItemID, strings.NewReader(`{"scheduled_for":"2026-09-01T09:00:00Z","values":{"location":"B"}}`))
	ur.SetPathValue("scheduledItemId", created.ScheduledItemID)
	urRec := httptest.NewRecorder()
	h.Update(urRec, member(ur))
	if urRec.Code != http.StatusOK {
		t.Fatalf("update want 200, got %d: %s", urRec.Code, urRec.Body.String())
	}
	var updated domain.ScheduledItem
	_ = json.Unmarshal(urRec.Body.Bytes(), &updated)
	if !updated.ScheduledFor.Equal(time.Date(2026, 9, 1, 9, 0, 0, 0, time.UTC)) || updated.Values["location"] != "B" {
		t.Fatalf("update not applied: %+v", updated)
	}

	// delete
	dr := httptest.NewRequest(http.MethodDelete, "/scheduled-items/"+created.ScheduledItemID, nil)
	dr.SetPathValue("scheduledItemId", created.ScheduledItemID)
	drRec := httptest.NewRecorder()
	h.Delete(drRec, member(dr))
	if drRec.Code != http.StatusNoContent {
		t.Fatalf("delete want 204, got %d", drRec.Code)
	}

	// get after delete → 404
	gr := httptest.NewRequest(http.MethodGet, "/scheduled-items/"+created.ScheduledItemID, nil)
	gr.SetPathValue("scheduledItemId", created.ScheduledItemID)
	grRec := httptest.NewRecorder()
	h.Get(grRec, member(gr))
	if grRec.Code != http.StatusNotFound {
		t.Fatalf("get after delete want 404, got %d", grRec.Code)
	}
}
