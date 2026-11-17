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

// CareInstructionsStore holds one row per receiver: the written instructions
// and the emergency contacts. Writes go through Stores, which checks the
// receiver in the same transaction.
type CareInstructionsStore struct {
	client *dynamodb.Client
	table  string
}

// Get returns the receiver's care instructions, or ErrNotFound when nothing
// has been written for them yet.
func (s *CareInstructionsStore) Get(ctx context.Context, receiverID string) (domain.CareInstructions, error) {
	return getItem[domain.CareInstructions](ctx, s.client, s.table, receiverKey(receiverID))
}

// SetCareInstructionsBody writes the receiver's instructions and stamps who
// changed them and when; an empty body removes the body and its stamp. The
// contacts are left as they are. It returns ErrNotFound if the receiver does
// not exist and ErrReceiverArchived if it is archived, and writes nothing then.
func (s *Stores) SetCareInstructionsBody(ctx context.Context, rc domain.Receiver, body, by string, at time.Time) error {
	u := &types.Update{
		TableName:                 aws.String(s.names.CareInstructions),
		Key:                       receiverKey(rc.ReceiverID),
		UpdateExpression:          aws.String("SET team_id = :t REMOVE body, updated_by, updated_at"),
		ExpressionAttributeValues: map[string]types.AttributeValue{":t": str(rc.TeamID)},
	}
	if body != "" {
		u.UpdateExpression = aws.String("SET team_id = :t, body = :b, updated_by = :by, updated_at = :at")
		u.ExpressionAttributeValues[":b"] = str(body)
		u.ExpressionAttributeValues[":by"] = str(by)
		u.ExpressionAttributeValues[":at"] = timeKey(at)
	}
	return s.writeCareInstructions(ctx, rc.ReceiverID, u)
}

// SetEmergencyContacts replaces the receiver's emergency contacts with the
// list given, in order. The body and its stamp are left as they are. Errors as
// SetCareInstructionsBody.
func (s *Stores) SetEmergencyContacts(ctx context.Context, rc domain.Receiver, contacts []domain.EmergencyContact) error {
	if contacts == nil {
		contacts = []domain.EmergencyContact{}
	}
	cv, err := attributevalue.Marshal(contacts)
	if err != nil {
		return err
	}
	return s.writeCareInstructions(ctx, rc.ReceiverID, &types.Update{
		TableName:                 aws.String(s.names.CareInstructions),
		Key:                       receiverKey(rc.ReceiverID),
		UpdateExpression:          aws.String("SET team_id = :t, contacts = :c"),
		ExpressionAttributeValues: map[string]types.AttributeValue{":t": str(rc.TeamID), ":c": cv},
	})
}

// writeCareInstructions applies u on condition, in the same transaction, that
// the receiver exists and is active.
func (s *Stores) writeCareInstructions(ctx context.Context, receiverID string, u *types.Update) error {
	_, err := s.client.TransactWriteItems(ctx, &dynamodb.TransactWriteItemsInput{
		TransactItems: []types.TransactWriteItem{
			{ConditionCheck: &types.ConditionCheck{
				TableName:                           aws.String(s.names.Receivers),
				Key:                                 receiverKey(receiverID),
				ConditionExpression:                 aws.String("attribute_exists(receiver_id) AND #s = :active"),
				ExpressionAttributeNames:            map[string]string{"#s": "status"},
				ExpressionAttributeValues:           map[string]types.AttributeValue{":active": str(string(domain.ReceiverActive))},
				ReturnValuesOnConditionCheckFailure: types.ReturnValuesOnConditionCheckFailureAllOld,
			}},
			{Update: u},
		},
	})
	var tce *types.TransactionCanceledException
	if !errors.As(err, &tce) {
		return err
	}
	if r := tce.CancellationReasons; len(r) > 0 && conditionFailed(r[0]) {
		if len(r[0].Item) == 0 {
			return ErrNotFound
		}
		return ErrReceiverArchived
	}
	return err
}
