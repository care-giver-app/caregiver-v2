package features_test

import (
	"context"
	"fmt"
	"net/http"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/cucumber/godog"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
)

// coverageWorld is a scenario's roster: the assignments and coverage
// schedules it made, and the list the API last showed of them.
type coverageWorld struct {
	assignments map[string]assignmentView // the caregiver's name as written → their assignment made last
	rules       map[string]string         // the caregiver's name as written → their coverage schedule's id
	shown       []assignmentView          // who is on duty, or the assignments ahead, as last read
	ruleList    []coverageScheduleView    // the coverage schedules as last read
	reread      func(context.Context) error
}

func newCoverageWorld() coverageWorld {
	return coverageWorld{assignments: map[string]assignmentView{}, rules: map[string]string{}}
}

// day is a local day a feature names: "today", "tomorrow" or "in 3 days".
const day = `(today|tomorrow|in \d+ days)`

// span is a time phrase a hand-made assignment starts at.
const span = `(\d+ (?:hours?|days?) (?:ago|from now))`

func (w *world) registerCoverage(sc *godog.ScenarioContext) {
	sc.Step(`^"([^"]*)" assigns "([^"]*)" to "([^"]*)" from `+span+` for (\d+) hours?$`, w.assignsFor)
	sc.Step(`^"([^"]*)" assigns "([^"]*)" to "([^"]*)" `+day+` from (\d\d:\d\d) to (\d\d:\d\d)$`, w.assignsOn)
	sc.Step(`^"([^"]*)" was on duty for "([^"]*)" from `+span+` for (\d+) hours?$`, w.wasOnDuty)
	sc.Step(`^"([^"]*)" hands "([^"]*)"'s assignment to "([^"]*)"$`, w.handsLast)
	sc.Step(`^"([^"]*)" hands "([^"]*)"'s assignment `+day+` on "([^"]*)" to "([^"]*)"$`, w.handsOn)
	sc.Step(`^"([^"]*)" removes "([^"]*)"'s assignment$`, w.removesLast)
	sc.Step(`^"([^"]*)" removes "([^"]*)"'s assignment `+day+` on "([^"]*)"$`, w.removesOn)

	sc.Step(`^"([^"]*)" schedules "([^"]*)" to cover "([^"]*)" every day from (\d\d:\d\d) to (\d\d:\d\d)(?: until `+day+`)?$`, w.schedulesCoverage)
	sc.Step(`^"([^"]*)" changes "([^"]*)"'s coverage schedule to every day from (\d\d:\d\d) to (\d\d:\d\d)$`, w.changesCoverage)
	sc.Step(`^"([^"]*)" removes "([^"]*)"'s coverage schedule$`, w.removesCoverage)

	sc.Step(`^"([^"]*)" opens who is on duty for "([^"]*)"$`, w.opensOnDuty)
	sc.Step(`^"([^"]*)" opens the assignments ahead of "([^"]*)"$`, w.opensAhead)
	sc.Step(`^"([^"]*)" opens the coverage schedules of "([^"]*)"$`, w.opensCoverage)

	sc.Step(`^nobody is listed$`, w.nobodyListed)
	sc.Step(`^on duty are `+quoted+`$`, w.onDutyAre)
	sc.Step(`^the assignments are by `+quoted+`, soonest first$`, w.assignmentsInOrder)
	sc.Step(`^"([^"]*)" is assigned `+day+` from (\d\d:\d\d) to (\d\d:\d\d)( the next day)?$`, w.isAssigned)
	sc.Step(`^"([^"]*)" is not assigned `+day+`$`, w.isNotAssigned)
	sc.Step(`^"([^"]*)"'s assignment `+day+` (belongs|does not belong) to a coverage schedule$`, w.belongsToRule)
	sc.Step(`^"([^"]*)"'s assignment `+day+` starts at (\d\d:\d\d) in "([^"]*)"$`, w.startsAtIn)
	sc.Step(`^the coverage schedules listed are for `+quoted+`$`, w.rulesListedFor)
	sc.Step(`^no coverage schedules are listed$`, w.noRulesListed)
	sc.Step(`^"([^"]*)"'s coverage schedule ends `+day+`$`, w.ruleEnds)
}

// ---- API shapes -------------------------------------------------------------

type assignmentView struct {
	AssignmentID       string `json:"assignment_id"`
	UserID             string `json:"user_id"`
	CaregiverName      string `json:"caregiver_name"`
	StartsLocal        string `json:"starts_local"`
	EndsLocal          string `json:"ends_local"`
	StartsAt           string `json:"starts_at"`
	EndsAt             string `json:"ends_at"`
	CoverageScheduleID string `json:"coverage_schedule_id"`
}

type coverageScheduleView struct {
	CoverageScheduleID string `json:"coverage_schedule_id"`
	UserID             string `json:"user_id"`
	CaregiverName      string `json:"caregiver_name"`
	StartTime          string `json:"start_time"`
	EndTime            string `json:"end_time"`
	StartsOn           string `json:"starts_on"`
	EndsOn             string `json:"ends_on"`
}

// ---- days and times ------------------------------------------------------------

var inDays = regexp.MustCompile(`^in (\d+) days$`)

// localDate is the receiver's local date a day phrase names.
func (w *world) localDate(phrase string) string {
	n := 0
	switch phrase {
	case "today":
	case "tomorrow":
		n = 1
	default:
		n, _ = strconv.Atoi(inDays.FindStringSubmatch(phrase)[1])
	}
	return w.care.now.In(zone()).AddDate(0, 0, n).Format(time.DateOnly)
}

func nextDate(date string) string {
	d, _ := time.Parse(time.DateOnly, date)
	return d.AddDate(0, 0, 1).Format(time.DateOnly)
}

// local is an instant as the receiver's local YYYY-MM-DDTHH:MM, to the minute.
func local(t time.Time) string { return t.In(zone()).Format("2006-01-02T15:04") }

// ---- making and changing assignments --------------------------------------------

func (w *world) assign(ctx context.Context, by, who, receiver, starts, ends string) error {
	p, err := w.person(ctx, by)
	if err != nil {
		return err
	}
	cg, err := w.person(ctx, who)
	if err != nil {
		return err
	}
	rc, err := w.receiver(receiver)
	if err != nil {
		return err
	}
	body := map[string]string{"user_id": cg.userID, "starts_local": starts, "ends_local": ends}
	if err := w.call(ctx, p, http.MethodPost, "/v1/receivers/"+rc.ReceiverID+"/assignments", body); err != nil {
		return err
	}
	if w.last.status == http.StatusCreated {
		a, err := decodeLast[assignmentView](w)
		if err != nil {
			return err
		}
		w.track(assignmentKey(w.d.db().names, a.AssignmentID))
		w.cov.assignments[who] = a
	}
	return nil
}

func (w *world) assignsFor(ctx context.Context, by, who, receiver, from string, hours int) error {
	start, err := w.at(from)
	if err != nil {
		return err
	}
	start = start.Truncate(time.Minute)
	return w.assign(ctx, by, who, receiver, local(start), local(start.Add(time.Duration(hours)*time.Hour)))
}

func (w *world) assignsOn(ctx context.Context, by, who, receiver, onDay, from, to string) error {
	date := w.localDate(onDay)
	endDate := date
	if to <= from {
		endDate = nextDate(date)
	}
	return w.assign(ctx, by, who, receiver, date+"T"+from, endDate+"T"+to)
}

// wasOnDuty writes an assignment that has already ended straight to the
// table: the API makes only ones that end in the future.
func (w *world) wasOnDuty(ctx context.Context, who, receiver, from string, hours int) error {
	cg, err := w.signedIn(ctx, who)
	if err != nil {
		return err
	}
	rc, err := w.receiver(receiver)
	if err != nil {
		return err
	}
	start, err := w.at(from)
	if err != nil {
		return err
	}
	start = start.Truncate(time.Minute)
	end := start.Add(time.Duration(hours) * time.Hour)
	a := domain.Assignment{
		AssignmentID: w.nextID("as"), ReceiverID: rc.ReceiverID, TeamID: rc.TeamID, UserID: cg.userID,
		StartsLocal: local(start), EndsLocal: local(end), StartsAt: start, EndsAt: end,
		Status: domain.AssignmentActive, CreatedBy: "features", CreatedAt: start.Add(-24 * time.Hour),
	}
	db := w.d.db()
	w.track(assignmentKey(db.names, a.AssignmentID))
	if err := db.put(ctx, db.names.Assignments, a); err != nil {
		return fmt.Errorf("could not write the assignment: %w", err)
	}
	w.cov.assignments[who] = assignmentView{AssignmentID: a.AssignmentID, UserID: a.UserID, StartsLocal: a.StartsLocal, EndsLocal: a.EndsLocal}
	return nil
}

// findOn finds whose assignment starts on a day, from the assignments ahead
// as an admin sees them.
func (w *world) findOn(ctx context.Context, by, who, onDay, receiver string) (assignmentView, error) {
	cg, err := w.person(ctx, who)
	if err != nil {
		return assignmentView{}, err
	}
	date := w.localDate(onDay)
	var found assignmentView
	err = eventually(ctx, fmt.Sprintf("%q's assignment %s", who, onDay), func(ctx context.Context) (bool, error) {
		if err := w.opensAhead(ctx, by, receiver); err != nil {
			return false, err
		}
		if w.last.status != http.StatusOK {
			return false, w.unexpected("the assignments ahead to load (200)")
		}
		for _, a := range w.cov.shown {
			if a.UserID == cg.userID && strings.HasPrefix(a.StartsLocal, date) {
				found = a
				return true, nil
			}
		}
		return false, nil
	})
	return found, err
}

func (w *world) hand(ctx context.Context, by string, a assignmentView, to string) error {
	p, err := w.person(ctx, by)
	if err != nil {
		return err
	}
	cg, err := w.person(ctx, to)
	if err != nil {
		return err
	}
	body := map[string]string{"user_id": cg.userID, "starts_local": a.StartsLocal, "ends_local": a.EndsLocal}
	if err := w.call(ctx, p, http.MethodPut, "/v1/assignments/"+a.AssignmentID, body); err != nil {
		return err
	}
	if w.last.status == http.StatusOK {
		changed, err := decodeLast[assignmentView](w)
		if err != nil {
			return err
		}
		w.cov.assignments[to] = changed
	}
	return nil
}

func (w *world) handsLast(ctx context.Context, by, who, to string) error {
	a, ok := w.cov.assignments[who]
	if !ok {
		return fmt.Errorf("the scenario never made an assignment for %q", who)
	}
	return w.hand(ctx, by, a, to)
}

func (w *world) handsOn(ctx context.Context, by, who, onDay, receiver, to string) error {
	a, err := w.findOn(ctx, by, who, onDay, receiver)
	if err != nil {
		return err
	}
	return w.hand(ctx, by, a, to)
}

func (w *world) remove(ctx context.Context, by, assignmentID string) error {
	p, err := w.person(ctx, by)
	if err != nil {
		return err
	}
	return w.call(ctx, p, http.MethodDelete, "/v1/assignments/"+assignmentID, nil)
}

func (w *world) removesLast(ctx context.Context, by, who string) error {
	a, ok := w.cov.assignments[who]
	if !ok {
		return fmt.Errorf("the scenario never made an assignment for %q", who)
	}
	return w.remove(ctx, by, a.AssignmentID)
}

func (w *world) removesOn(ctx context.Context, by, who, onDay, receiver string) error {
	a, err := w.findOn(ctx, by, who, onDay, receiver)
	if err != nil {
		return err
	}
	return w.remove(ctx, by, a.AssignmentID)
}

// ---- coverage schedules ------------------------------------------------------------

func everyDayRule(cgID, from, to string) map[string]any {
	return map[string]any{
		"user_id":    cgID,
		"rule":       map[string]any{"freq": "weekly", "interval": 1, "by_day": []string{"MO", "TU", "WE", "TH", "FR", "SA", "SU"}},
		"start_time": from, "end_time": to,
	}
}

func (w *world) schedulesCoverage(ctx context.Context, by, who, receiver, from, to, until string) error {
	p, err := w.person(ctx, by)
	if err != nil {
		return err
	}
	cg, err := w.person(ctx, who)
	if err != nil {
		return err
	}
	rc, err := w.receiver(receiver)
	if err != nil {
		return err
	}
	body := everyDayRule(cg.userID, from, to)
	if until != "" {
		body["ends_on"] = w.localDate(until)
	}
	if err := w.call(ctx, p, http.MethodPost, "/v1/receivers/"+rc.ReceiverID+"/coverage-schedules", body); err != nil {
		return err
	}
	if w.last.status == http.StatusCreated {
		cs, err := decodeLast[coverageScheduleView](w)
		if err != nil {
			return err
		}
		w.track(coverageScheduleKey(w.d.db().names, cs.CoverageScheduleID))
		w.cov.rules[who] = cs.CoverageScheduleID
	}
	return nil
}

func (w *world) ruleOf(who string) (string, error) {
	id, ok := w.cov.rules[who]
	if !ok {
		return "", fmt.Errorf("the scenario never made a coverage schedule for %q", who)
	}
	return id, nil
}

func (w *world) changesCoverage(ctx context.Context, by, who, from, to string) error {
	p, err := w.person(ctx, by)
	if err != nil {
		return err
	}
	id, err := w.ruleOf(who)
	if err != nil {
		return err
	}
	return w.call(ctx, p, http.MethodPut, "/v1/coverage-schedules/"+id, everyDayRule(w.people[who].userID, from, to))
}

func (w *world) removesCoverage(ctx context.Context, by, who string) error {
	p, err := w.person(ctx, by)
	if err != nil {
		return err
	}
	id, err := w.ruleOf(who)
	if err != nil {
		return err
	}
	return w.call(ctx, p, http.MethodDelete, "/v1/coverage-schedules/"+id, nil)
}

// ---- reading the roster -------------------------------------------------------------

func (w *world) readAssignments(ctx context.Context, label, receiver, what string) error {
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	rc, err := w.receiver(receiver)
	if err != nil {
		return err
	}
	w.cov.reread = func(ctx context.Context) error {
		if err := w.call(ctx, p, http.MethodGet, "/v1/receivers/"+rc.ReceiverID+"/"+what, nil); err != nil {
			return err
		}
		w.cov.shown = nil
		if w.last.status == http.StatusOK {
			as, err := decodeLast[[]assignmentView](w)
			if err != nil {
				return err
			}
			w.cov.shown = as
		}
		return nil
	}
	return w.cov.reread(ctx)
}

func (w *world) opensOnDuty(ctx context.Context, label, receiver string) error {
	return w.readAssignments(ctx, label, receiver, "on-duty")
}

func (w *world) opensAhead(ctx context.Context, label, receiver string) error {
	return w.readAssignments(ctx, label, receiver, "assignments")
}

func (w *world) opensCoverage(ctx context.Context, label, receiver string) error {
	p, err := w.person(ctx, label)
	if err != nil {
		return err
	}
	rc, err := w.receiver(receiver)
	if err != nil {
		return err
	}
	w.cov.reread = func(ctx context.Context) error {
		if err := w.call(ctx, p, http.MethodGet, "/v1/receivers/"+rc.ReceiverID+"/coverage-schedules", nil); err != nil {
			return err
		}
		w.cov.ruleList = nil
		if w.last.status == http.StatusOK {
			rules, err := decodeLast[[]coverageScheduleView](w)
			if err != nil {
				return err
			}
			w.cov.ruleList = rules
		}
		return nil
	}
	return w.cov.reread(ctx)
}

// settled checks what the roster last showed, reading it again for up to ten
// seconds while it does not hold: the roster is read through eventually
// consistent indexes, which on dev can lag a write made a moment before.
func (w *world) settled(ctx context.Context, check func() error) error {
	deadline := time.Now().Add(10 * time.Second)
	for {
		if w.last.status != http.StatusOK {
			return w.unexpected("the roster to load (200)")
		}
		err := check()
		if err == nil || time.Now().After(deadline) || w.cov.reread == nil {
			return err
		}
		time.Sleep(200 * time.Millisecond)
		if err := w.cov.reread(ctx); err != nil {
			return err
		}
	}
}

func (w *world) nobodyListed(ctx context.Context) error {
	return w.settled(ctx, func() error {
		if w.cov.shown == nil || len(w.cov.shown) != 0 {
			return w.unexpected("nobody to be listed (an empty list)")
		}
		return nil
	})
}

func (w *world) onDutyAre(ctx context.Context, list string) error {
	want := names(list)
	sort.Strings(want)
	return w.settled(ctx, func() error {
		var got []string
		for _, a := range w.cov.shown {
			got = append(got, a.CaregiverName)
		}
		sort.Strings(got)
		if strings.Join(got, "|") != strings.Join(want, "|") {
			return fmt.Errorf("expected on duty %q, but were %q", want, got)
		}
		return nil
	})
}

func (w *world) assignmentsInOrder(ctx context.Context, list string) error {
	want := names(list)
	return w.settled(ctx, func() error {
		var got []string
		for _, a := range w.cov.shown {
			got = append(got, a.CaregiverName)
		}
		if strings.Join(got, "|") != strings.Join(want, "|") {
			return fmt.Errorf("expected assignments by %q, soonest first, but they were by %q", want, got)
		}
		return nil
	})
}

// onDay is the caregiver's assignments starting on the day, as last shown.
// It matches by who they are, not by name, so one who has left — and so is
// no longer named — is still found.
func (w *world) onDay(who, date string) ([]assignmentView, error) {
	p := w.people[who]
	if p == nil {
		return nil, fmt.Errorf("%q has not appeared in this scenario", who)
	}
	var out []assignmentView
	for _, a := range w.cov.shown {
		if a.UserID == p.userID && strings.HasPrefix(a.StartsLocal, date) {
			out = append(out, a)
		}
	}
	return out, nil
}

func (w *world) isAssigned(ctx context.Context, who, onDay, from, to, nextDay string) error {
	date := w.localDate(onDay)
	endDate := date
	if nextDay != "" {
		endDate = nextDate(date)
	}
	want := fmt.Sprintf("%s %sT%s–%sT%s", who, date, from, endDate, to)
	return w.settled(ctx, func() error {
		as, err := w.onDay(who, date)
		if err != nil {
			return err
		}
		var got []string
		for _, a := range as {
			got = append(got, fmt.Sprintf("%s %s–%s", a.CaregiverName, a.StartsLocal, a.EndsLocal))
		}
		if len(got) != 1 || got[0] != want {
			return fmt.Errorf("expected exactly one assignment %q, but %q %s had %q", want, who, onDay, got)
		}
		return nil
	})
}

func (w *world) isNotAssigned(ctx context.Context, who, onDay string) error {
	date := w.localDate(onDay)
	return w.settled(ctx, func() error {
		as, err := w.onDay(who, date)
		if err != nil {
			return err
		}
		if len(as) != 0 {
			return fmt.Errorf("expected %q not to be assigned %s, but they were: %+v", who, onDay, as)
		}
		return nil
	})
}

func (w *world) belongsToRule(ctx context.Context, who, onDay, belongs string) error {
	date := w.localDate(onDay)
	return w.settled(ctx, func() error {
		as, err := w.onDay(who, date)
		if err != nil {
			return err
		}
		if len(as) != 1 {
			return fmt.Errorf("expected one assignment for %q %s, but there were %d", who, onDay, len(as))
		}
		if (as[0].CoverageScheduleID != "") != (belongs == "belongs") {
			return fmt.Errorf("expected %q's assignment %s to %s to a coverage schedule, but its coverage_schedule_id is %q",
				who, onDay, belongs, as[0].CoverageScheduleID)
		}
		return nil
	})
}

func (w *world) startsAtIn(ctx context.Context, who, onDay, hhmm, tz string) error {
	loc, err := time.LoadLocation(tz)
	if err != nil {
		return err
	}
	date := w.localDate(onDay)
	return w.settled(ctx, func() error {
		as, err := w.onDay(who, date)
		if err != nil {
			return err
		}
		if len(as) != 1 {
			return fmt.Errorf("expected one assignment for %q %s, but there were %d", who, onDay, len(as))
		}
		at, err := time.Parse(time.RFC3339, as[0].StartsAt)
		if err != nil {
			return err
		}
		if got := at.In(loc).Format("15:04"); got != hhmm {
			return fmt.Errorf("expected %q's assignment %s to start at %s in %s, but it starts at %s there (%s)", who, onDay, hhmm, tz, got, as[0].StartsAt)
		}
		return nil
	})
}

func (w *world) rulesListedFor(ctx context.Context, list string) error {
	var want []string
	for _, label := range names(list) {
		p := w.people[label]
		if p == nil {
			return fmt.Errorf("%q has not appeared in this scenario", label)
		}
		want = append(want, p.userID)
	}
	sort.Strings(want)
	return w.settled(ctx, func() error {
		var got []string
		for _, cs := range w.cov.ruleList {
			got = append(got, cs.UserID)
		}
		sort.Strings(got)
		if strings.Join(got, "|") != strings.Join(want, "|") {
			return w.unexpected(fmt.Sprintf("coverage schedules for %s", list))
		}
		return nil
	})
}

func (w *world) noRulesListed(ctx context.Context) error {
	return w.settled(ctx, func() error {
		if w.cov.ruleList == nil || len(w.cov.ruleList) != 0 {
			return w.unexpected("no coverage schedules to be listed (an empty list)")
		}
		return nil
	})
}

func (w *world) ruleEnds(ctx context.Context, who, onDay string) error {
	id, err := w.ruleOf(who)
	if err != nil {
		return err
	}
	date := w.localDate(onDay)
	return w.settled(ctx, func() error {
		for _, cs := range w.cov.ruleList {
			if cs.CoverageScheduleID == id {
				if cs.EndsOn != date {
					return w.unexpected(fmt.Sprintf("%q's coverage schedule to end %s (%s)", who, onDay, date))
				}
				return nil
			}
		}
		return w.unexpected(fmt.Sprintf("%q's coverage schedule to be listed", who))
	})
}

// ---- cleanup ------------------------------------------------------------------------

// trackRoster tracks, for cleanup, every assignment on a receiver the
// scenario made, including those its coverage schedules generated.
func (w *world) trackRoster(ctx context.Context) error {
	db := w.d.db()
	for _, rc := range w.care.receivers {
		in := &dynamodb.QueryInput{
			TableName:                 aws.String(db.names.Assignments),
			IndexName:                 aws.String("receiver-time"),
			KeyConditionExpression:    aws.String("receiver_id = :r"),
			ProjectionExpression:      aws.String("assignment_id"),
			ExpressionAttributeValues: map[string]types.AttributeValue{":r": s(rc.ReceiverID)},
		}
		for {
			out, err := db.client.Query(ctx, in)
			if err != nil {
				return fmt.Errorf("find the assignments of receiver %s: %w", rc.ReceiverID, err)
			}
			for _, item := range out.Items {
				w.track(rowKey{db.names.Assignments, map[string]types.AttributeValue{"assignment_id": item["assignment_id"]}})
			}
			if len(out.LastEvaluatedKey) == 0 {
				break
			}
			in.ExclusiveStartKey = out.LastEvaluatedKey
		}
	}
	return nil
}
