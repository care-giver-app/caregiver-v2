package v1

import (
	"context"
	"errors"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	cip "github.com/aws/aws-sdk-go-v2/service/cognitoidentityprovider"
	ciptypes "github.com/aws/aws-sdk-go-v2/service/cognitoidentityprovider/types"
)

type fakeCognito struct {
	authErr, updateErr, deleteErr error
	auth                          *cip.AdminInitiateAuthInput
	update                        *cip.AdminUpdateUserAttributesInput
	del                           *cip.AdminDeleteUserInput
}

func (f *fakeCognito) AdminInitiateAuth(_ context.Context, in *cip.AdminInitiateAuthInput, _ ...func(*cip.Options)) (*cip.AdminInitiateAuthOutput, error) {
	f.auth = in
	if f.authErr != nil {
		return nil, f.authErr
	}
	return &cip.AdminInitiateAuthOutput{}, nil
}

func (f *fakeCognito) AdminUpdateUserAttributes(_ context.Context, in *cip.AdminUpdateUserAttributesInput, _ ...func(*cip.Options)) (*cip.AdminUpdateUserAttributesOutput, error) {
	f.update = in
	if f.updateErr != nil {
		return nil, f.updateErr
	}
	return &cip.AdminUpdateUserAttributesOutput{}, nil
}

func (f *fakeCognito) AdminDeleteUser(_ context.Context, in *cip.AdminDeleteUserInput, _ ...func(*cip.Options)) (*cip.AdminDeleteUserOutput, error) {
	f.del = in
	if f.deleteErr != nil {
		return nil, f.deleteErr
	}
	return &cip.AdminDeleteUserOutput{}, nil
}

func TestCognitoIdentity_CheckPassword(t *testing.T) {
	ctx := context.Background()
	fc := &fakeCognito{}
	id := &cognitoIdentity{api: fc, poolID: "pool", clientID: "client"}

	if err := id.CheckPassword(ctx, "sam@x.com", "pw"); err != nil {
		t.Fatal(err)
	}
	if fc.auth.AuthFlow != ciptypes.AuthFlowTypeAdminUserPasswordAuth || aws.ToString(fc.auth.ClientId) != "client" ||
		aws.ToString(fc.auth.UserPoolId) != "pool" || fc.auth.AuthParameters["USERNAME"] != "sam@x.com" ||
		fc.auth.AuthParameters["PASSWORD"] != "pw" {
		t.Fatalf("auth input = %+v", fc.auth)
	}

	for name, tc := range map[string]struct {
		err  error
		want error
	}{
		"wrong password":    {&ciptypes.NotAuthorizedException{Message: aws.String("Incorrect username or password.")}, ErrWrongPassword},
		"locked out":        {&ciptypes.NotAuthorizedException{Message: aws.String("Password attempts exceeded")}, ErrTooManyAttempts},
		"too many requests": {&ciptypes.TooManyRequestsException{}, ErrTooManyAttempts},
		"too many failed":   {&ciptypes.TooManyFailedAttemptsException{}, ErrTooManyAttempts},
		"limit exceeded":    {&ciptypes.LimitExceededException{}, ErrTooManyAttempts},
		"no such user":      {&ciptypes.UserNotFoundException{}, ErrWrongPassword},
	} {
		fc.authErr = tc.err
		if err := id.CheckPassword(ctx, "sam@x.com", "pw"); !errors.Is(err, tc.want) {
			t.Errorf("%s: got %v, want %v", name, err, tc.want)
		}
	}
	other := errors.New("network")
	fc.authErr = other
	if err := id.CheckPassword(ctx, "sam@x.com", "pw"); !errors.Is(err, other) {
		t.Errorf("other failures pass through: %v", err)
	}
}

func TestCognitoIdentity_StartEmailChange(t *testing.T) {
	ctx := context.Background()
	fc := &fakeCognito{}
	id := &cognitoIdentity{api: fc, poolID: "pool", clientID: "client"}

	if err := id.StartEmailChange(ctx, "sub-1", "new@x.com"); err != nil {
		t.Fatal(err)
	}
	if aws.ToString(fc.update.Username) != "sub-1" || len(fc.update.UserAttributes) != 1 ||
		aws.ToString(fc.update.UserAttributes[0].Name) != "email" || aws.ToString(fc.update.UserAttributes[0].Value) != "new@x.com" {
		t.Fatalf("update input = %+v", fc.update)
	}
	for name, tc := range map[string]struct {
		err  error
		want error
	}{
		"alias exists":    {&ciptypes.AliasExistsException{}, ErrEmailInUse},
		"username exists": {&ciptypes.UsernameExistsException{}, ErrEmailInUse},
		"too many":        {&ciptypes.TooManyRequestsException{}, ErrTooManyAttempts},
		"limit exceeded":  {&ciptypes.LimitExceededException{}, ErrTooManyAttempts},
	} {
		fc.updateErr = tc.err
		if err := id.StartEmailChange(ctx, "sub-1", "new@x.com"); !errors.Is(err, tc.want) {
			t.Errorf("%s: got %v", name, err)
		}
	}
}

func TestCognitoIdentity_DeleteUser(t *testing.T) {
	ctx := context.Background()
	fc := &fakeCognito{}
	id := &cognitoIdentity{api: fc, poolID: "pool", clientID: "client"}
	if err := id.DeleteUser(ctx, "sub-1"); err != nil || aws.ToString(fc.del.Username) != "sub-1" {
		t.Fatalf("delete: %v %+v", err, fc.del)
	}
	fc.deleteErr = &ciptypes.UserNotFoundException{}
	if err := id.DeleteUser(ctx, "sub-1"); err != nil {
		t.Fatalf("already gone: %v", err)
	}
	fc.deleteErr = errors.New("network")
	if err := id.DeleteUser(ctx, "sub-1"); err == nil {
		t.Fatal("a failure must be reported")
	}
}
