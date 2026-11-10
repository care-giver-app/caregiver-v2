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

type JournalNoteStore struct {
	client *dynamodb.Client
	table  string
}

func journalNoteKey(noteID string) map[string]types.AttributeValue {
	return map[string]types.AttributeValue{"note_id": &types.AttributeValueMemberS{Value: noteID}}
}

// Get returns one journal note, or ErrNotFound.
func (s *JournalNoteStore) Get(ctx context.Context, noteID string) (domain.JournalNote, error) {
	return getItem[domain.JournalNote](ctx, s.client, s.table, journalNoteKey(noteID))
}

// ListByReceiverBetween returns the receiver's notes whose at is in [from, to),
// oldest first, via the receiver-time index. It reads to the end: the caller
// bounds it to one local day.
func (s *JournalNoteStore) ListByReceiverBetween(ctx context.Context, receiverID string, from, to time.Time) ([]domain.JournalNote, error) {
	if !to.After(from) {
		return nil, nil
	}
	return queryAll[domain.JournalNote](ctx, s.client, &dynamodb.QueryInput{
		TableName:                aws.String(s.table),
		IndexName:                aws.String(receiverTime),
		KeyConditionExpression:   aws.String("receiver_id = :r AND #at BETWEEN :from AND :to"),
		ExpressionAttributeNames: map[string]string{"#at": "at"},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":r":    &types.AttributeValueMemberS{Value: receiverID},
			":from": timeKey(from),
			":to":   timeKey(to.Add(-time.Nanosecond)),
		},
		ScanIndexForward: aws.Bool(true),
	})
}

// Create writes a new note. The put is conditional so an id collision fails
// with a ConditionalCheckFailedException instead of overwriting.
func (s *JournalNoteStore) Create(ctx context.Context, n domain.JournalNote) error {
	item, err := MarshalItem(n)
	if err != nil {
		return err
	}
	_, err = s.client.PutItem(ctx, &dynamodb.PutItemInput{
		TableName:           aws.String(s.table),
		Item:                item,
		ConditionExpression: aws.String("attribute_not_exists(note_id)"),
	})
	return err
}

// Put writes Edit journal note's Save — at and body — and records by and at as
// who changed it last and when. The author and created_at stay. It returns the
// note as stored, or ErrNotFound if it no longer exists.
func (s *JournalNoteStore) Put(ctx context.Context, noteID string, at time.Time, body, by string, now time.Time) (domain.JournalNote, error) {
	out, err := s.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName:                aws.String(s.table),
		Key:                      journalNoteKey(noteID),
		UpdateExpression:         aws.String("SET #at = :at, #body = :body, updated_by = :by, updated_at = :now"),
		ConditionExpression:      aws.String("attribute_exists(note_id)"),
		ExpressionAttributeNames: map[string]string{"#at": "at", "#body": "body"},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":at":   timeKey(at),
			":body": &types.AttributeValueMemberS{Value: body},
			":by":   &types.AttributeValueMemberS{Value: by},
			":now":  timeKey(now),
		},
		ReturnValues: types.ReturnValueAllNew,
	})
	var ccf *types.ConditionalCheckFailedException
	if errors.As(err, &ccf) {
		return domain.JournalNote{}, ErrNotFound
	}
	if err != nil {
		return domain.JournalNote{}, err
	}
	var n domain.JournalNote
	if err := attributevalue.UnmarshalMap(out.Attributes, &n); err != nil {
		return domain.JournalNote{}, err
	}
	return n, nil
}

// Delete removes the note. It returns ErrNotFound if it was already gone.
func (s *JournalNoteStore) Delete(ctx context.Context, noteID string) error {
	_, err := s.client.DeleteItem(ctx, &dynamodb.DeleteItemInput{
		TableName:           aws.String(s.table),
		Key:                 journalNoteKey(noteID),
		ConditionExpression: aws.String("attribute_exists(note_id)"),
	})
	var ccf *types.ConditionalCheckFailedException
	if errors.As(err, &ccf) {
		return ErrNotFound
	}
	return err
}
