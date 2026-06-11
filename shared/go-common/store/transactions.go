package store

import (
	"context"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/domain"
)

// CreateCareGroupWithAdmin writes the group and the creator's admin membership
// atomically. The group write is conditional so an id collision fails cleanly.
func (s *Stores) CreateCareGroupWithAdmin(ctx context.Context, g domain.CareGroup, m domain.Membership) error {
	gi, err := attributevalue.MarshalMap(g)
	if err != nil {
		return err
	}
	mi, err := attributevalue.MarshalMap(m)
	if err != nil {
		return err
	}
	_, err = s.client.TransactWriteItems(ctx, &dynamodb.TransactWriteItemsInput{
		TransactItems: []types.TransactWriteItem{
			{Put: &types.Put{
				TableName:           aws.String(s.names.CareGroups),
				Item:                gi,
				ConditionExpression: aws.String("attribute_not_exists(care_group_id)"),
			}},
			{Put: &types.Put{TableName: aws.String(s.names.Memberships), Item: mi}},
		},
	})
	return err
}

// AcceptInvitation atomically flips a pending invitation to accepted and writes
// the membership. The pending condition makes concurrent accepts safe: exactly
// one transaction wins.
func (s *Stores) AcceptInvitation(ctx context.Context, token string, m domain.Membership) error {
	mi, err := attributevalue.MarshalMap(m)
	if err != nil {
		return err
	}
	_, err = s.client.TransactWriteItems(ctx, &dynamodb.TransactWriteItemsInput{
		TransactItems: []types.TransactWriteItem{
			{Update: &types.Update{
				TableName:                aws.String(s.names.Invitations),
				Key:                      map[string]types.AttributeValue{"token": &types.AttributeValueMemberS{Value: token}},
				UpdateExpression:         aws.String("SET #s = :accepted"),
				ConditionExpression:      aws.String("#s = :pending"),
				ExpressionAttributeNames: map[string]string{"#s": "status"},
				ExpressionAttributeValues: map[string]types.AttributeValue{
					":accepted": &types.AttributeValueMemberS{Value: string(domain.InviteAccepted)},
					":pending":  &types.AttributeValueMemberS{Value: string(domain.InvitePending)},
				},
			}},
			{Put: &types.Put{TableName: aws.String(s.names.Memberships), Item: mi}},
		},
	})
	return err
}
