package v1

import (
	"context"
	"errors"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	cip "github.com/aws/aws-sdk-go-v2/service/cognitoidentityprovider"
	ciptypes "github.com/aws/aws-sdk-go-v2/service/cognitoidentityprovider/types"
)

// What the identity provider can refuse, as the Settings handlers answer it.
var (
	// ErrWrongPassword: the password is not right (403 WrongPassword).
	ErrWrongPassword = errors.New("the password is not right")
	// ErrTooManyAttempts: the provider's own limit on tries (429 TooManyAttempts).
	ErrTooManyAttempts = errors.New("too many tries in a short time; try again later")
	// ErrEmailInUse: another account already uses the address (409 EmailInUse).
	ErrEmailInUse = errors.New("another account already uses that address")
)

// IdentityProvider is the part of the identity provider (Cognito) that Change
// email and Close account need. Every account lives there as well as in the
// user table; the token the API is called with comes from it.
type IdentityProvider interface {
	// CheckPassword reports whether password is the account's current one.
	// signIn is what the caregiver signs in with (their address). It returns
	// ErrWrongPassword or ErrTooManyAttempts when it is not, or cannot be
	// checked now.
	CheckPassword(ctx context.Context, signIn, password string) error
	// StartEmailChange asks for the account's address to become newEmail,
	// which is sent a code. The old address stays in force until the code is
	// confirmed. It returns ErrEmailInUse when another account has newEmail.
	StartEmailChange(ctx context.Context, userID, newEmail string) error
	// DeleteUser removes the account from the identity provider, so it can no
	// longer sign in and its address can sign up again. An account already
	// gone is not an error.
	DeleteUser(ctx context.Context, userID string) error
}

// cognitoAPI is the slice of the Cognito client cognitoIdentity calls.
type cognitoAPI interface {
	AdminInitiateAuth(context.Context, *cip.AdminInitiateAuthInput, ...func(*cip.Options)) (*cip.AdminInitiateAuthOutput, error)
	AdminUpdateUserAttributes(context.Context, *cip.AdminUpdateUserAttributesInput, ...func(*cip.Options)) (*cip.AdminUpdateUserAttributesOutput, error)
	AdminDeleteUser(context.Context, *cip.AdminDeleteUserInput, ...func(*cip.Options)) (*cip.AdminDeleteUserOutput, error)
}

// cognitoIdentity is IdentityProvider on a Cognito user pool. The pool signs
// in by email, so a user's Cognito username is their sub — the user_id — and
// the admin calls name them by it.
type cognitoIdentity struct {
	api      cognitoAPI
	poolID   string
	clientID string
}

// NewCognitoIdentity wraps a Cognito client for the pool and its app client.
// The app client has no secret and allows ADMIN_USER_PASSWORD_AUTH.
func NewCognitoIdentity(client *cip.Client, poolID, clientID string) IdentityProvider {
	return &cognitoIdentity{api: client, poolID: poolID, clientID: clientID}
}

func (c *cognitoIdentity) CheckPassword(ctx context.Context, signIn, password string) error {
	_, err := c.api.AdminInitiateAuth(ctx, &cip.AdminInitiateAuthInput{
		UserPoolId:     aws.String(c.poolID),
		ClientId:       aws.String(c.clientID),
		AuthFlow:       ciptypes.AuthFlowTypeAdminUserPasswordAuth,
		AuthParameters: map[string]string{"USERNAME": signIn, "PASSWORD": password},
	})
	// A challenge (MFA, a new password) still means the password was right;
	// the tokens it would have issued are not wanted.
	return passwordError(err)
}

// passwordError maps what AdminInitiateAuth refused with. Cognito's lockout
// after repeated wrong passwords is a NotAuthorizedException whose message is
// "Password attempts exceeded", so the message is what tells it from a wrong
// password.
func passwordError(err error) error {
	if err == nil {
		return nil
	}
	var na *ciptypes.NotAuthorizedException
	if errors.As(err, &na) {
		if strings.Contains(strings.ToLower(na.ErrorMessage()), "attempts exceeded") {
			return ErrTooManyAttempts
		}
		return ErrWrongPassword
	}
	var (
		tmr *ciptypes.TooManyRequestsException
		tmf *ciptypes.TooManyFailedAttemptsException
		le  *ciptypes.LimitExceededException
		unf *ciptypes.UserNotFoundException
	)
	switch {
	case errors.As(err, &tmr), errors.As(err, &tmf), errors.As(err, &le):
		return ErrTooManyAttempts
	case errors.As(err, &unf):
		// The pool hides unknown users behind NotAuthorized; answer alike.
		return ErrWrongPassword
	}
	return err
}

func (c *cognitoIdentity) StartEmailChange(ctx context.Context, userID, newEmail string) error {
	// The pool keeps the original address until the new one is verified, so
	// this only sends the code; the old address still signs in meanwhile.
	_, err := c.api.AdminUpdateUserAttributes(ctx, &cip.AdminUpdateUserAttributesInput{
		UserPoolId:     aws.String(c.poolID),
		Username:       aws.String(userID),
		UserAttributes: []ciptypes.AttributeType{{Name: aws.String("email"), Value: aws.String(newEmail)}},
	})
	var (
		ae  *ciptypes.AliasExistsException
		ue  *ciptypes.UsernameExistsException
		tmr *ciptypes.TooManyRequestsException
		le  *ciptypes.LimitExceededException
	)
	switch {
	case err == nil:
		return nil
	case errors.As(err, &ae), errors.As(err, &ue):
		return ErrEmailInUse
	case errors.As(err, &tmr), errors.As(err, &le):
		return ErrTooManyAttempts
	}
	return err
}

func (c *cognitoIdentity) DeleteUser(ctx context.Context, userID string) error {
	_, err := c.api.AdminDeleteUser(ctx, &cip.AdminDeleteUserInput{
		UserPoolId: aws.String(c.poolID),
		Username:   aws.String(userID),
	})
	var unf *ciptypes.UserNotFoundException
	if errors.As(err, &unf) {
		return nil
	}
	return err
}
