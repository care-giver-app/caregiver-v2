package store

import (
	"context"
	"errors"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
)

// ErrReceiverArchived is returned by writes refused because the care receiver
// is archived, and everything about them is read-only until restored.
var ErrReceiverArchived = errors.New("care receiver is archived")

type ReceiverStore struct {
	client *dynamodb.Client
	table  string
}

func receiverKey(receiverID string) map[string]types.AttributeValue {
	return map[string]types.AttributeValue{"receiver_id": &types.AttributeValueMemberS{Value: receiverID}}
}

func (s *ReceiverStore) Get(ctx context.Context, receiverID string) (domain.Receiver, error) {
	return getItem[domain.Receiver](ctx, s.client, s.table, receiverKey(receiverID))
}

// Create writes a new receiver. The put is conditional so an id collision
// fails instead of overwriting.
func (s *ReceiverStore) Create(ctx context.Context, rc domain.Receiver) error {
	item, err := MarshalItem(rc)
	if err != nil {
		return err
	}
	_, err = s.client.PutItem(ctx, &dynamodb.PutItemInput{
		TableName:           aws.String(s.table),
		Item:                item,
		ConditionExpression: aws.String("attribute_not_exists(receiver_id)"),
	})
	return err
}

// ListActiveByTeam returns the team's active receivers, oldest first.
func (s *ReceiverStore) ListActiveByTeam(ctx context.Context, teamID string) ([]domain.Receiver, error) {
	return s.ListByTeam(ctx, teamID, domain.ReceiverActive)
}

// ListByTeam returns the team's receivers in the given status, oldest first.
func (s *ReceiverStore) ListByTeam(ctx context.Context, teamID string, status domain.ReceiverStatus) ([]domain.Receiver, error) {
	return queryAll[domain.Receiver](ctx, s.client, &dynamodb.QueryInput{
		TableName:                aws.String(s.table),
		IndexName:                aws.String(teamIndex),
		KeyConditionExpression:   aws.String("team_id = :t"),
		FilterExpression:         aws.String("#s = :status"),
		ExpressionAttributeNames: map[string]string{"#s": "status"},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":t":      &types.AttributeValueMemberS{Value: teamID},
			":status": &types.AttributeValueMemberS{Value: string(status)},
		},
		ScanIndexForward: aws.Bool(true),
	})
}

// Change writes an active receiver's name and time zone and returns it as
// stored. It returns ErrNotFound if the receiver does not exist and
// ErrReceiverArchived if it is archived. Re-resolving its scheduled entries in
// a new zone is the caller's.
func (s *ReceiverStore) Change(ctx context.Context, receiverID, name, timeZone string) (domain.Receiver, error) {
	out, err := s.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName:                aws.String(s.table),
		Key:                      receiverKey(receiverID),
		UpdateExpression:         aws.String("SET #n = :n, time_zone = :tz"),
		ConditionExpression:      aws.String("attribute_exists(receiver_id) AND #s = :active"),
		ExpressionAttributeNames: map[string]string{"#n": "name", "#s": "status"},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":n":      &types.AttributeValueMemberS{Value: name},
			":tz":     &types.AttributeValueMemberS{Value: timeZone},
			":active": &types.AttributeValueMemberS{Value: string(domain.ReceiverActive)},
		},
		ReturnValues:                        types.ReturnValueAllNew,
		ReturnValuesOnConditionCheckFailure: types.ReturnValuesOnConditionCheckFailureAllOld,
	})
	var ccf *types.ConditionalCheckFailedException
	if errors.As(err, &ccf) {
		if len(ccf.Item) == 0 {
			return domain.Receiver{}, ErrNotFound
		}
		return domain.Receiver{}, ErrReceiverArchived
	} else if err != nil {
		return domain.Receiver{}, err
	}
	var rc domain.Receiver
	if err := attributevalue.UnmarshalMap(out.Attributes, &rc); err != nil {
		return domain.Receiver{}, err
	}
	return rc, nil
}

// SetStatus archives or restores a receiver and returns it as stored.
// Archiving sets archived_by/archived_at; restoring removes them. A receiver
// already in the status is returned unchanged, so a repeat keeps the original
// archived_at. It returns ErrNotFound if the receiver does not exist.
func (s *ReceiverStore) SetStatus(ctx context.Context, receiverID string, status domain.ReceiverStatus, by string, at time.Time) (domain.Receiver, error) {
	if status != domain.ReceiverActive && status != domain.ReceiverArchived {
		return domain.Receiver{}, errors.New("invalid receiver status")
	}
	update := "SET #s = :s REMOVE archived_by, archived_at"
	vals := map[string]types.AttributeValue{":s": &types.AttributeValueMemberS{Value: string(status)}}
	if status == domain.ReceiverArchived {
		update = "SET #s = :s, archived_by = :by, archived_at = :at"
		vals[":by"] = &types.AttributeValueMemberS{Value: by}
		vals[":at"] = timeKey(at)
	}
	out, err := s.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName:                           aws.String(s.table),
		Key:                                 receiverKey(receiverID),
		UpdateExpression:                    aws.String(update),
		ConditionExpression:                 aws.String("attribute_exists(receiver_id) AND #s <> :s"),
		ExpressionAttributeNames:            map[string]string{"#s": "status"},
		ExpressionAttributeValues:           vals,
		ReturnValues:                        types.ReturnValueAllNew,
		ReturnValuesOnConditionCheckFailure: types.ReturnValuesOnConditionCheckFailureAllOld,
	})
	var item map[string]types.AttributeValue
	if err == nil {
		item = out.Attributes
	} else {
		var ccf *types.ConditionalCheckFailedException
		if !errors.As(err, &ccf) {
			return domain.Receiver{}, err
		}
		if len(ccf.Item) == 0 {
			return domain.Receiver{}, ErrNotFound
		}
		item = ccf.Item // already in that status
	}
	var rc domain.Receiver
	if err := attributevalue.UnmarshalMap(item, &rc); err != nil {
		return domain.Receiver{}, err
	}
	return rc, nil
}
