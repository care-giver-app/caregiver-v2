package store

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
)

// ErrEntryNotInState is returned by the entry writes below when the entry is
// no longer in the state the write needs: somebody settled it first, or
// changed it in a way that took it out of that state.
var ErrEntryNotInState = errors.New("entry not in state")

// Every settling write sets or removes the whole care side, so the row says
// exactly one thing whatever it said before. The note is part of the care: an
// empty one is removed rather than stored.

// Log records care against a scheduled entry: logged by by at now, occurred at
// c.OccurredAt, holding c's values and note. It leaves the open index and
// sorts by when the care happened. It is conditional on the entry still being
// scheduled, so of two caregivers logging or skipping it at once exactly one
// wins; the other gets ErrEntryNotInState. An entry that does not exist gives
// ErrNotFound.
func (s *EntryStore) Log(ctx context.Context, entryID string, c domain.EntryCare, by string, now time.Time) (domain.Entry, error) {
	u := newEntryUpdate()
	u.set("#s", "state", str(string(domain.EntryLogged)))
	if err := u.setCare(c); err != nil {
		return domain.Entry{}, err
	}
	u.set("", "logged_by", str(by))
	u.set("", "logged_at", timeKey(now))
	u.remove("open_at", "skipped_by", "skipped_at")
	return s.update(ctx, entryID, u, "#s = :from", map[string]types.AttributeValue{":from": str(string(domain.EntryScheduled))})
}

// Skip settles a scheduled entry as not happening: skipped by by at now, with
// note saying why ("" for none). Its values and its place in the timeline, at
// its occurrence time, stay. Conditional on it still being scheduled, as Log
// is.
func (s *EntryStore) Skip(ctx context.Context, entryID, note, by string, now time.Time) (domain.Entry, error) {
	u := newEntryUpdate()
	u.set("#s", "state", str(string(domain.EntrySkipped)))
	u.setNote(note)
	u.set("", "skipped_by", str(by))
	u.set("", "skipped_at", timeKey(now))
	u.remove("open_at", "occurred_at", "logged_by", "logged_at")
	return s.update(ctx, entryID, u, "#s = :from", map[string]types.AttributeValue{":from": str(string(domain.EntryScheduled))})
}

// Change saves Edit entry on an entry read in state from (logged or skipped),
// recording by and now as who changed it last and when. Editing a skipped
// entry logs it: by becomes who logged it, at now, and the skip is cleared.
// Conditional on the entry still being in state from, so an edit made from a
// stale read of it fails with ErrEntryNotInState rather than reviving a state
// it has since left.
func (s *EntryStore) Change(ctx context.Context, entryID string, from domain.EntryState, c domain.EntryCare, by string, now time.Time) (domain.Entry, error) {
	if from != domain.EntryLogged && from != domain.EntrySkipped {
		return domain.Entry{}, ErrEntryNotInState
	}
	u := newEntryUpdate()
	if err := u.setCare(c); err != nil {
		return domain.Entry{}, err
	}
	u.set("", "updated_by", str(by))
	u.set("", "updated_at", timeKey(now))
	if from == domain.EntrySkipped {
		u.set("#s", "state", str(string(domain.EntryLogged)))
		u.set("", "logged_by", str(by))
		u.set("", "logged_at", timeKey(now))
		u.remove("skipped_by", "skipped_at")
	}
	return s.update(ctx, entryID, u, "#s = :from", map[string]types.AttributeValue{":from": str(string(from))})
}

// Reopen undoes the log or skip of a planned entry read in state from: it is
// scheduled again, with its planned values back, none of its care (occurred
// at, note, who logged or skipped it and when), and back in the open index at
// its occurrence time — unrecorded if that has passed. by and now are recorded
// as who changed it last. Conditional on it still being in state from and
// still planned.
func (s *EntryStore) Reopen(ctx context.Context, e domain.Entry, by string, now time.Time) (domain.Entry, error) {
	if e.OccurrenceAt == nil || (e.State != domain.EntryLogged && e.State != domain.EntrySkipped) {
		return domain.Entry{}, ErrEntryNotInState
	}
	planned := e.PlannedValues
	if planned == nil {
		planned = map[string]any{}
	}
	vals, err := attributevalue.Marshal(planned)
	if err != nil {
		return domain.Entry{}, err
	}
	u := newEntryUpdate()
	u.set("#s", "state", str(string(domain.EntryScheduled)))
	u.set("#v", "values", vals)
	u.set("", "timeline_at", timeKey(*e.OccurrenceAt))
	u.set("", "open_at", timeKey(*e.OccurrenceAt))
	u.set("", "updated_by", str(by))
	u.set("", "updated_at", timeKey(now))
	u.setNote("")
	u.remove("occurred_at", "logged_by", "logged_at", "skipped_by", "skipped_at")
	return s.update(ctx, e.EntryID, u, "#s = :from AND attribute_exists(occurrence_at)",
		map[string]types.AttributeValue{":from": str(string(e.State))})
}

// DeleteAdHoc removes an entry logged ad hoc, read in state from. Conditional
// on it still being in that state and having no plan, so a planned entry is
// never removed this way.
func (s *EntryStore) DeleteAdHoc(ctx context.Context, entryID string, from domain.EntryState) error {
	_, err := s.client.DeleteItem(ctx, &dynamodb.DeleteItemInput{
		TableName:                           aws.String(s.table),
		Key:                                 entryKey(entryID),
		ConditionExpression:                 aws.String("#s = :from AND attribute_not_exists(occurrence_at)"),
		ExpressionAttributeNames:            map[string]string{"#s": "state"},
		ExpressionAttributeValues:           map[string]types.AttributeValue{":from": str(string(from))},
		ReturnValuesOnConditionCheckFailure: types.ReturnValuesOnConditionCheckFailureAllOld,
	})
	return conditionErr(err)
}

// conditionErr turns a failed condition into ErrNotFound when the item was
// not there at all, and ErrEntryNotInState when it was.
func conditionErr(err error) error {
	var ccf *types.ConditionalCheckFailedException
	if errors.As(err, &ccf) {
		if len(ccf.Item) == 0 {
			return ErrNotFound
		}
		return ErrEntryNotInState
	}
	return err
}

func str(s string) types.AttributeValue { return &types.AttributeValueMemberS{Value: s} }

// entryUpdate assembles an UpdateItem's SET and REMOVE clauses.
type entryUpdate struct {
	sets    []string
	removes []string
	names   map[string]string
	values  map[string]types.AttributeValue
}

func newEntryUpdate() *entryUpdate {
	return &entryUpdate{names: map[string]string{"#s": "state"}, values: map[string]types.AttributeValue{}}
}

// set adds "attr = :attr". A non-empty alias stands for attr, for names
// DynamoDB reserves (state, values, note).
func (u *entryUpdate) set(alias, attr string, v types.AttributeValue) {
	ref := attr
	if alias != "" {
		ref, u.names[alias] = alias, attr
	}
	u.sets = append(u.sets, ref+" = :"+attr)
	u.values[":"+attr] = v
}

func (u *entryUpdate) remove(refs ...string) { u.removes = append(u.removes, refs...) }

// setCare sets what EntryCare records: values, occurred_at and the timeline
// position it gives a logged entry, and the note.
func (u *entryUpdate) setCare(c domain.EntryCare) error {
	vals := c.Values
	if vals == nil {
		vals = map[string]any{}
	}
	av, err := attributevalue.Marshal(vals)
	if err != nil {
		return err
	}
	u.set("#v", "values", av)
	u.set("", "occurred_at", timeKey(c.OccurredAt))
	u.set("", "timeline_at", timeKey(c.OccurredAt))
	u.setNote(c.Note)
	return nil
}

func (u *entryUpdate) setNote(note string) {
	if note == "" {
		u.names["#n"] = "note"
		u.remove("#n")
		return
	}
	u.set("#n", "note", str(note))
}

func (u *entryUpdate) expression() string {
	expr := ""
	if len(u.sets) > 0 {
		expr = "SET " + strings.Join(u.sets, ", ")
	}
	if len(u.removes) > 0 {
		if expr != "" {
			expr += " "
		}
		expr += "REMOVE " + strings.Join(u.removes, ", ")
	}
	return expr
}

// update applies u on condition cond, returning the entry as stored after it.
func (s *EntryStore) update(ctx context.Context, entryID string, u *entryUpdate, cond string, condValues map[string]types.AttributeValue) (domain.Entry, error) {
	for k, v := range condValues {
		u.values[k] = v
	}
	out, err := s.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName:                           aws.String(s.table),
		Key:                                 entryKey(entryID),
		UpdateExpression:                    aws.String(u.expression()),
		ConditionExpression:                 aws.String(cond),
		ExpressionAttributeNames:            u.names,
		ExpressionAttributeValues:           u.values,
		ReturnValues:                        types.ReturnValueAllNew,
		ReturnValuesOnConditionCheckFailure: types.ReturnValuesOnConditionCheckFailureAllOld,
	})
	if err := conditionErr(err); err != nil {
		return domain.Entry{}, err
	}
	var e domain.Entry
	if err := attributevalue.UnmarshalMap(out.Attributes, &e); err != nil {
		return domain.Entry{}, err
	}
	return e, nil
}
