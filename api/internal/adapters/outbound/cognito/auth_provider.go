package cognito

import (
	"context"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/cognitoidentityprovider"
	"github.com/aws/aws-sdk-go-v2/service/cognitoidentityprovider/types"

	"github.com/rafaelcmd/internal-developer-platform/api/internal/domain/errors"
	"github.com/rafaelcmd/internal-developer-platform/api/internal/domain/model"
	"github.com/rafaelcmd/internal-developer-platform/api/internal/domain/ports/outbound"
)

// CognitoAuthProvider implements the AuthProvider interface using AWS Cognito.
type CognitoAuthProvider struct {
	client   *cognitoidentityprovider.Client
	clientID string
}

// Ensure CognitoAuthProvider implements the AuthProvider interface.
var _ outbound.AuthProvider = (*CognitoAuthProvider)(nil)

// NewCognitoAuthProvider creates a new CognitoAuthProvider.
func NewCognitoAuthProvider(client *cognitoidentityprovider.Client, clientID string) *CognitoAuthProvider {
	return &CognitoAuthProvider{
		client:   client,
		clientID: clientID,
	}
}

// SignUp registers a new user in Cognito.
func (p *CognitoAuthProvider) SignUp(ctx context.Context, email, password string) error {
	_, err := p.client.SignUp(ctx, &cognitoidentityprovider.SignUpInput{
		ClientId: aws.String(p.clientID),
		Username: aws.String(email),
		Password: aws.String(password),
		UserAttributes: []types.AttributeType{
			{
				Name:  aws.String("email"),
				Value: aws.String(email),
			},
		},
	})
	if err != nil {
		return errors.NewDomainError(
			errors.ErrCodeUserAlreadyExists,
			"failed to register user",
			err,
		)
	}
	return nil
}

// SignIn authenticates a user and returns tokens.
func (p *CognitoAuthProvider) SignIn(ctx context.Context, email, password string) (*model.AuthResponse, error) {
	output, err := p.client.InitiateAuth(ctx, &cognitoidentityprovider.InitiateAuthInput{
		AuthFlow: types.AuthFlowTypeUserPasswordAuth,
		ClientId: aws.String(p.clientID),
		AuthParameters: map[string]string{
			"USERNAME": email,
			"PASSWORD": password,
		},
	})
	if err != nil {
		return nil, errors.NewDomainError(
			errors.ErrCodeInvalidCredentials,
			"authentication failed",
			err,
		)
	}

	if output.AuthenticationResult == nil {
		return nil, errors.NewDomainError(
			errors.ErrCodeAuthFailed,
			"authentication failed: no result returned",
			errors.ErrUnauthorized,
		)
	}

	return &model.AuthResponse{
		AccessToken:  aws.ToString(output.AuthenticationResult.AccessToken),
		RefreshToken: aws.ToString(output.AuthenticationResult.RefreshToken),
		IdToken:      aws.ToString(output.AuthenticationResult.IdToken),
		ExpiresIn:    output.AuthenticationResult.ExpiresIn,
		TokenType:    aws.ToString(output.AuthenticationResult.TokenType),
	}, nil
}

// ConfirmSignUp confirms a user's email with the confirmation code.
func (p *CognitoAuthProvider) ConfirmSignUp(ctx context.Context, email, confirmationCode string) error {
	_, err := p.client.ConfirmSignUp(ctx, &cognitoidentityprovider.ConfirmSignUpInput{
		ClientId:         aws.String(p.clientID),
		Username:         aws.String(email),
		ConfirmationCode: aws.String(confirmationCode),
	})
	if err != nil {
		return errors.NewDomainError(
			errors.ErrCodeInvalidConfirmationCode,
			"failed to confirm user registration",
			err,
		)
	}
	return nil
}
