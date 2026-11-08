package store

import (
	"encoding/base64"
	"encoding/json"
	"errors"

	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
)

// ErrInvalidCursor is returned when a page cursor was not one this store
// issued for that query. Handlers map it to 400.
var ErrInvalidCursor = errors.New("invalid cursor")

// encodeCursor turns a LastEvaluatedKey whose attributes are all strings into
// an opaque cursor: base64url (unpadded) of a JSON object of those strings.
// An empty key encodes to "", meaning the last page.
func encodeCursor(lek map[string]types.AttributeValue) (string, error) {
	if len(lek) == 0 {
		return "", nil
	}
	m := make(map[string]string, len(lek))
	for k, v := range lek {
		s, ok := v.(*types.AttributeValueMemberS)
		if !ok {
			return "", errors.New("cursor: non-string key attribute " + k)
		}
		m[k] = s.Value
	}
	b, err := json.Marshal(m)
	if err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

// decodeCursor reverses encodeCursor, requiring exactly the given key
// attributes so a tampered cursor fails here rather than at DynamoDB. An empty
// cursor decodes to a nil key (the first page).
func decodeCursor(s string, keys ...string) (map[string]types.AttributeValue, error) {
	if s == "" {
		return nil, nil
	}
	b, err := base64.RawURLEncoding.DecodeString(s)
	if err != nil {
		return nil, ErrInvalidCursor
	}
	var m map[string]string
	if err := json.Unmarshal(b, &m); err != nil || len(m) != len(keys) {
		return nil, ErrInvalidCursor
	}
	lek := make(map[string]types.AttributeValue, len(keys))
	for _, k := range keys {
		v, ok := m[k]
		if !ok || v == "" {
			return nil, ErrInvalidCursor
		}
		lek[k] = &types.AttributeValueMemberS{Value: v}
	}
	return lek, nil
}
