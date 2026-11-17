package store

import (
	"context"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"

	"github.com/care-giver-app/caregiver-v2/shared/go-common/v1/domain"
)

// SetTeamIndexView makes changeMember see the team-index as view returns it,
// given what the index actually holds, until restore is called. It stands in
// for an eventually consistent index lagging the table.
func SetTeamIndexView(view func(ctx context.Context, s *Stores, members []domain.Membership) []domain.Membership) (restore func()) {
	was := listTeamIndex
	listTeamIndex = func(ctx context.Context, s *Stores, teamID string) ([]domain.Membership, error) {
		ms, err := was(ctx, s, teamID)
		if err != nil {
			return nil, err
		}
		return view(ctx, s, ms), nil
	}
	return func() { listTeamIndex = was }
}

// RemoveMemberRow deletes a membership row outright, as a concurrent leave
// would.
func (s *Stores) RemoveMemberRow(ctx context.Context, userID, teamID string) error {
	_, err := s.client.DeleteItem(ctx, &dynamodb.DeleteItemInput{TableName: aws.String(s.names.Memberships), Key: membershipKey(userID, teamID)})
	return err
}
