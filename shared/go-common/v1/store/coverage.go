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

// CoverageScheduleStore reads and writes coverage schedules: the recurring
// rules that generate a receiver's assignments.
type CoverageScheduleStore struct {
	client *dynamodb.Client
	table  string
}

func coverageScheduleKey(id string) map[string]types.AttributeValue {
	return map[string]types.AttributeValue{"coverage_schedule_id": str(id)}
}

// liveCoverageCond is the condition every write to a live coverage schedule
// carries: it exists and has not been removed.
const liveCoverageCond = "attribute_exists(coverage_schedule_id) AND attribute_not_exists(removed_at)"

// Create writes a new coverage schedule. The put is conditional so an id
// collision fails instead of overwriting.
func (s *CoverageScheduleStore) Create(ctx context.Context, cs domain.CoverageSchedule) error {
	item, err := MarshalItem(cs)
	if err != nil {
		return err
	}
	_, err = s.client.PutItem(ctx, &dynamodb.PutItemInput{
		TableName:           aws.String(s.table),
		Item:                item,
		ConditionExpression: aws.String("attribute_not_exists(coverage_schedule_id)"),
	})
	return err
}

// Get returns the coverage schedule, removed or not, or ErrNotFound.
func (s *CoverageScheduleStore) Get(ctx context.Context, id string) (domain.CoverageSchedule, error) {
	return getItem[domain.CoverageSchedule](ctx, s.client, s.table, coverageScheduleKey(id))
}

// ListLiveByReceiver returns the receiver's coverage schedules that have not
// been removed, ended or not, oldest first.
func (s *CoverageScheduleStore) ListLiveByReceiver(ctx context.Context, receiverID string) ([]domain.CoverageSchedule, error) {
	return queryAll[domain.CoverageSchedule](ctx, s.client, &dynamodb.QueryInput{
		TableName:                 aws.String(s.table),
		IndexName:                 aws.String(receiverIndex),
		KeyConditionExpression:    aws.String("receiver_id = :r"),
		FilterExpression:          aws.String("attribute_not_exists(removed_at)"),
		ExpressionAttributeValues: map[string]types.AttributeValue{":r": str(receiverID)},
		ScanIndexForward:          aws.Bool(true),
	})
}

// Update writes A coverage schedule's Save onto a live rule: who covers, the
// rule, the hours, ends_on (removed when empty) and updated_at. starts_on,
// removal and the bookmark are untouched. It returns the rule as stored, or
// ErrNotFound if it does not exist or has been removed.
func (s *CoverageScheduleStore) Update(ctx context.Context, cs domain.CoverageSchedule) (domain.CoverageSchedule, error) {
	item, err := MarshalItem(cs)
	if err != nil {
		return domain.CoverageSchedule{}, err
	}
	set := "SET user_id = :u, #rule = :rule, start_time = :st, end_time = :et, updated_at = :at"
	vals := map[string]types.AttributeValue{
		":u": item["user_id"], ":rule": item["rule"], ":st": item["start_time"], ":et": item["end_time"], ":at": item["updated_at"],
	}
	names := map[string]string{"#rule": "rule"}
	if v, ok := item["ends_on"]; ok {
		set += ", ends_on = :e"
		vals[":e"] = v
	} else {
		set += " REMOVE ends_on"
	}
	out, err := s.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName:                 aws.String(s.table),
		Key:                       coverageScheduleKey(cs.CoverageScheduleID),
		UpdateExpression:          aws.String(set),
		ConditionExpression:       aws.String(liveCoverageCond),
		ExpressionAttributeNames:  names,
		ExpressionAttributeValues: vals,
		ReturnValues:              types.ReturnValueAllNew,
	})
	var ccf *types.ConditionalCheckFailedException
	if errors.As(err, &ccf) {
		return domain.CoverageSchedule{}, ErrNotFound
	} else if err != nil {
		return domain.CoverageSchedule{}, err
	}
	var stored domain.CoverageSchedule
	if err := attributevalue.UnmarshalMap(out.Attributes, &stored); err != nil {
		return domain.CoverageSchedule{}, err
	}
	return stored, nil
}

// EndOn ends a live rule on endsOn (a local date), and moves its updated_at to
// at so a generator running at the same moment takes back what it wrote. A
// rule that already ends on or before endsOn is left as it is. It reports
// whether it changed the rule.
func (s *CoverageScheduleStore) EndOn(ctx context.Context, id, endsOn string, at time.Time) (bool, error) {
	_, err := s.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName:           aws.String(s.table),
		Key:                 coverageScheduleKey(id),
		UpdateExpression:    aws.String("SET ends_on = :e, updated_at = :at"),
		ConditionExpression: aws.String(liveCoverageCond + " AND (attribute_not_exists(ends_on) OR ends_on > :e)"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":e": str(endsOn), ":at": timeKey(at),
		},
	})
	var ccf *types.ConditionalCheckFailedException
	if errors.As(err, &ccf) {
		return false, nil
	}
	return err == nil, err
}

// MarkRemoved sets removed_at on a live rule. It returns ErrNotFound if the
// rule does not exist or was already removed.
func (s *CoverageScheduleStore) MarkRemoved(ctx context.Context, id string, at time.Time) error {
	_, err := s.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName:                 aws.String(s.table),
		Key:                       coverageScheduleKey(id),
		UpdateExpression:          aws.String("SET removed_at = :at"),
		ConditionExpression:       aws.String(liveCoverageCond),
		ExpressionAttributeValues: map[string]types.AttributeValue{":at": timeKey(at)},
	})
	var ccf *types.ConditionalCheckFailedException
	if errors.As(err, &ccf) {
		return ErrNotFound
	}
	return err
}

// SetGeneratedThrough records the generator's bookmark on a live rule that has
// not changed since the copy the generator worked from (its updated_at is still
// updatedAt). It returns ErrNotFound if the rule is gone, removed or changed.
func (s *CoverageScheduleStore) SetGeneratedThrough(ctx context.Context, id, through string, updatedAt time.Time) error {
	_, err := s.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName:           aws.String(s.table),
		Key:                 coverageScheduleKey(id),
		UpdateExpression:    aws.String("SET generated_through = :g"),
		ConditionExpression: aws.String(liveCoverageCond + " AND updated_at = :u"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":g": str(through), ":u": timeKey(updatedAt),
		},
	})
	var ccf *types.ConditionalCheckFailedException
	if errors.As(err, &ccf) {
		return ErrNotFound
	}
	return err
}

// ListLive returns every coverage schedule, on every team, that has not been
// removed, for the daily generator. It scans the table, which is fine at
// family scale.
func (s *CoverageScheduleStore) ListLive(ctx context.Context) ([]domain.CoverageSchedule, error) {
	in := &dynamodb.ScanInput{
		TableName:        aws.String(s.table),
		FilterExpression: aws.String("attribute_not_exists(removed_at)"),
	}
	var all []domain.CoverageSchedule
	for {
		out, err := s.client.Scan(ctx, in)
		if err != nil {
			return nil, err
		}
		var page []domain.CoverageSchedule
		if err := attributevalue.UnmarshalListOfMaps(out.Items, &page); err != nil {
			return nil, err
		}
		all = append(all, page...)
		if len(out.LastEvaluatedKey) == 0 {
			return all, nil
		}
		in.ExclusiveStartKey = out.LastEvaluatedKey
	}
}

// ErrAssignmentEnded is returned by changes refused because the assignment
// has already ended: it stays as it is, saying who was responsible.
var ErrAssignmentEnded = errors.New("assignment has ended")

// AssignmentStore reads and writes assignments.
type AssignmentStore struct {
	client *dynamodb.Client
	table  string
}

func assignmentKey(id string) map[string]types.AttributeValue {
	return map[string]types.AttributeValue{"assignment_id": str(id)}
}

// Create writes a new assignment, failing on an id collision.
func (s *AssignmentStore) Create(ctx context.Context, a domain.Assignment) error {
	created, err := s.CreateIfAbsent(ctx, a)
	if err == nil && !created {
		return errors.New("assignment id already exists")
	}
	return err
}

// CreateIfAbsent writes an assignment unless one with its id already exists,
// and reports whether it wrote it. A generated assignment's id is
// deterministic, so a slot already made — or changed or removed by hand since
// — is never made twice.
func (s *AssignmentStore) CreateIfAbsent(ctx context.Context, a domain.Assignment) (bool, error) {
	item, err := MarshalItem(a)
	if err != nil {
		return false, err
	}
	_, err = s.client.PutItem(ctx, &dynamodb.PutItemInput{
		TableName:           aws.String(s.table),
		Item:                item,
		ConditionExpression: aws.String("attribute_not_exists(assignment_id)"),
	})
	var ccf *types.ConditionalCheckFailedException
	if errors.As(err, &ccf) {
		return false, nil
	}
	return err == nil, err
}

// Get returns the assignment, removed or not, or ErrNotFound.
func (s *AssignmentStore) Get(ctx context.Context, id string) (domain.Assignment, error) {
	return getItem[domain.Assignment](ctx, s.client, s.table, assignmentKey(id))
}

// NotEndedByReceiver returns the receiver's active assignments that end after
// now — in progress or still ahead — soonest start first.
//
// The receiver-time index sorts on starts_at, and an assignment in progress
// may have started any time before now, however long ago: there is no bound
// below which none can still be running. So it reads the receiver's whole
// partition and keeps what ends after now. That grows with the receiver's
// history, a few rows a day at family scale.
func (s *AssignmentStore) NotEndedByReceiver(ctx context.Context, receiverID string, now time.Time) ([]domain.Assignment, error) {
	return queryAll[domain.Assignment](ctx, s.client, &dynamodb.QueryInput{
		TableName:                aws.String(s.table),
		IndexName:                aws.String(receiverTime),
		KeyConditionExpression:   aws.String("receiver_id = :r"),
		FilterExpression:         aws.String("ends_at > :now AND #s = :active"),
		ExpressionAttributeNames: map[string]string{"#s": "status"},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":r": str(receiverID), ":now": timeKey(now), ":active": str(string(domain.AssignmentActive)),
		},
		ScanIndexForward: aws.Bool(true),
	})
}

// DeleteFutureForSchedule deletes the rule's assignments that start after now
// and still belong to it — what changing or removing the rule redraws. Ones
// changed or removed by hand (detached) stay, as does anything already begun.
// Each delete is conditional, so one detached meanwhile survives. It returns
// how many went.
func (s *AssignmentStore) DeleteFutureForSchedule(ctx context.Context, coverageScheduleID string, now time.Time) (int, error) {
	in := &dynamodb.QueryInput{
		TableName:              aws.String(s.table),
		IndexName:              aws.String(coverageScheduleIndex),
		KeyConditionExpression: aws.String("coverage_schedule_id = :c AND starts_at > :now"),
		FilterExpression:       aws.String("attribute_not_exists(detached_at)"),
		ProjectionExpression:   aws.String("assignment_id"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":c": str(coverageScheduleID), ":now": timeKey(now),
		},
	}
	deleted := 0
	for {
		out, err := s.client.Query(ctx, in)
		if err != nil {
			return deleted, err
		}
		for _, item := range out.Items {
			id, ok := item["assignment_id"].(*types.AttributeValueMemberS)
			if !ok {
				continue
			}
			gone, err := s.DeleteIfAttached(ctx, id.Value)
			if err != nil {
				return deleted, err
			}
			if gone {
				deleted++
			}
		}
		if len(out.LastEvaluatedKey) == 0 {
			return deleted, nil
		}
		in.ExclusiveStartKey = out.LastEvaluatedKey
	}
}

// DeleteIfAttached deletes a generated assignment that still belongs to its
// rule, and reports whether it did. One detached meanwhile stays.
func (s *AssignmentStore) DeleteIfAttached(ctx context.Context, id string) (bool, error) {
	_, err := s.client.DeleteItem(ctx, &dynamodb.DeleteItemInput{
		TableName:                aws.String(s.table),
		Key:                      assignmentKey(id),
		ConditionExpression:      aws.String("attribute_exists(coverage_schedule_id) AND attribute_not_exists(detached_at) AND #s = :active"),
		ExpressionAttributeNames: map[string]string{"#s": "status"},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":active": str(string(domain.AssignmentActive)),
		},
	})
	var ccf *types.ConditionalCheckFailedException
	if errors.As(err, &ccf) {
		return false, nil
	}
	return err == nil, err
}

// notEndedCond holds a hand change to an assignment that is still active and
// has not ended.
const notEndedCond = "attribute_exists(assignment_id) AND #s = :active AND ends_at > :now"

// assignmentConditionErr maps a refused hand change to ErrNotFound (gone or removed) or
// ErrAssignmentEnded, from the row as it stood.
func assignmentConditionErr(old map[string]types.AttributeValue) error {
	if len(old) == 0 {
		return ErrNotFound
	}
	var a domain.Assignment
	if err := attributevalue.UnmarshalMap(old, &a); err != nil {
		return err
	}
	if a.Status != domain.AssignmentActive {
		return ErrNotFound
	}
	return ErrAssignmentEnded
}

// Change writes a hand change onto an active assignment that has not ended at
// now: who covers, its times, and who changed it when. A generated one is
// detached from its rule (detached_at, set once). It returns the assignment as
// stored, ErrNotFound if it is gone or removed, or ErrAssignmentEnded.
func (s *AssignmentStore) Change(ctx context.Context, a domain.Assignment, by string, now time.Time) (domain.Assignment, error) {
	item, err := MarshalItem(a)
	if err != nil {
		return domain.Assignment{}, err
	}
	set := []string{
		"user_id = :u", "starts_local = :sl", "ends_local = :el", "starts_at = :sa", "ends_at = :ea",
		"updated_by = :by", "updated_at = :now",
	}
	if a.Generated() {
		set = append(set, "detached_at = if_not_exists(detached_at, :now)")
	}
	out, err := s.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName:                aws.String(s.table),
		Key:                      assignmentKey(a.AssignmentID),
		UpdateExpression:         aws.String("SET " + strings.Join(set, ", ")),
		ConditionExpression:      aws.String(notEndedCond),
		ExpressionAttributeNames: map[string]string{"#s": "status"},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":u": item["user_id"], ":sl": item["starts_local"], ":el": item["ends_local"],
			":sa": item["starts_at"], ":ea": item["ends_at"], ":by": str(by), ":now": timeKey(now),
			":active": str(string(domain.AssignmentActive)),
		},
		ReturnValues:                        types.ReturnValueAllNew,
		ReturnValuesOnConditionCheckFailure: types.ReturnValuesOnConditionCheckFailureAllOld,
	})
	var ccf *types.ConditionalCheckFailedException
	if errors.As(err, &ccf) {
		return domain.Assignment{}, assignmentConditionErr(ccf.Item)
	} else if err != nil {
		return domain.Assignment{}, err
	}
	var stored domain.Assignment
	if err := attributevalue.UnmarshalMap(out.Attributes, &stored); err != nil {
		return domain.Assignment{}, err
	}
	return stored, nil
}

// Remove drops an active assignment that has not ended at now. One made by
// hand is deleted. One a rule made is kept as a removed, detached row, so the
// rule does not make that slot again. It returns ErrNotFound if the
// assignment is gone or already removed, or ErrAssignmentEnded.
func (s *AssignmentStore) Remove(ctx context.Context, a domain.Assignment, by string, now time.Time) error {
	vals := map[string]types.AttributeValue{
		":now": timeKey(now), ":active": str(string(domain.AssignmentActive)),
	}
	var err error
	if a.Generated() {
		vals[":removed"] = str(string(domain.AssignmentRemoved))
		vals[":by"] = str(by)
		_, err = s.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
			TableName:                           aws.String(s.table),
			Key:                                 assignmentKey(a.AssignmentID),
			UpdateExpression:                    aws.String("SET #s = :removed, detached_at = if_not_exists(detached_at, :now), updated_by = :by, updated_at = :now"),
			ConditionExpression:                 aws.String(notEndedCond),
			ExpressionAttributeNames:            map[string]string{"#s": "status"},
			ExpressionAttributeValues:           vals,
			ReturnValuesOnConditionCheckFailure: types.ReturnValuesOnConditionCheckFailureAllOld,
		})
	} else {
		_, err = s.client.DeleteItem(ctx, &dynamodb.DeleteItemInput{
			TableName:                           aws.String(s.table),
			Key:                                 assignmentKey(a.AssignmentID),
			ConditionExpression:                 aws.String(notEndedCond),
			ExpressionAttributeNames:            map[string]string{"#s": "status"},
			ExpressionAttributeValues:           vals,
			ReturnValuesOnConditionCheckFailure: types.ReturnValuesOnConditionCheckFailureAllOld,
		})
	}
	var ccf *types.ConditionalCheckFailedException
	if errors.As(err, &ccf) {
		return assignmentConditionErr(ccf.Item)
	}
	return err
}

// Retime moves an active assignment that has not started to new instants,
// keeping its local times — what a receiver's time zone changing does. It is
// conditional on the local times being as read and the assignment still
// active, and reports whether it moved it.
func (s *AssignmentStore) Retime(ctx context.Context, a domain.Assignment, startsAt, endsAt time.Time) (bool, error) {
	_, err := s.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName:                aws.String(s.table),
		Key:                      assignmentKey(a.AssignmentID),
		UpdateExpression:         aws.String("SET starts_at = :sa, ends_at = :ea"),
		ConditionExpression:      aws.String("#s = :active AND starts_local = :sl AND ends_local = :el"),
		ExpressionAttributeNames: map[string]string{"#s": "status"},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":sa": timeKey(startsAt), ":ea": timeKey(endsAt),
			":sl": str(a.StartsLocal), ":el": str(a.EndsLocal),
			":active": str(string(domain.AssignmentActive)),
		},
	})
	var ccf *types.ConditionalCheckFailedException
	if errors.As(err, &ccf) {
		return false, nil
	}
	return err == nil, err
}

// EndNow ends an assignment in progress at now — what leaving the team does
// to a shift they are part-way through. endsLocal is now in the receiver's
// zone. A generated one is detached from its rule. It reports whether it
// changed it: one already ended, removed or gone is left alone.
func (s *AssignmentStore) EndNow(ctx context.Context, a domain.Assignment, endsLocal, by string, now time.Time) (bool, error) {
	set := "SET ends_local = :el, ends_at = :now, updated_by = :by, updated_at = :now"
	if a.Generated() {
		set += ", detached_at = if_not_exists(detached_at, :now)"
	}
	_, err := s.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName:                aws.String(s.table),
		Key:                      assignmentKey(a.AssignmentID),
		UpdateExpression:         aws.String(set),
		ConditionExpression:      aws.String(notEndedCond),
		ExpressionAttributeNames: map[string]string{"#s": "status"},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":el": str(endsLocal), ":now": timeKey(now), ":by": str(by),
			":active": str(string(domain.AssignmentActive)),
		},
	})
	var ccf *types.ConditionalCheckFailedException
	if errors.As(err, &ccf) {
		return false, nil
	}
	return err == nil, err
}
