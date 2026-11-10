package domain

import "time"

// JournalNote is a note about a receiver's day, at the time it is about.
// Author is the user_id of who wrote it and stays theirs through edits;
// UpdatedBy and UpdatedAt are absent until it is first changed.
type JournalNote struct {
	NoteID     string     `dynamodbav:"note_id"`
	ReceiverID string     `dynamodbav:"receiver_id"`
	TeamID     string     `dynamodbav:"team_id"`
	At         time.Time  `dynamodbav:"at"`
	Body       string     `dynamodbav:"body"`
	Author     string     `dynamodbav:"author"`
	CreatedAt  time.Time  `dynamodbav:"created_at"`
	UpdatedBy  string     `dynamodbav:"updated_by,omitempty"`
	UpdatedAt  *time.Time `dynamodbav:"updated_at,omitempty"`
}
