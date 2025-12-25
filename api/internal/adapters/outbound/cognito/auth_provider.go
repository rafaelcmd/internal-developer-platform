package cognito

import (
	"context"
	"fmt"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/cognitoidentityprovider"
	"github.com/aws/aws-sdk-go-v2/service/cognitoidentityprovider/types"
	"github.com/rafaelcmd/internal-developer-platform/api/internal/domain/model"
)

type CognitoAuthProvider struct {
	client   *cognitoidentityprovider.Client
	clientID string
}

func NewCognitoAuthProvider(client *cognitoidentityprovider.Client, clientID string) *CognitoAuthProvider {
	return &CognitoAuthProvider{
		client:   client,
		clientID: clientID,
	}
}

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
	return err
}

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
		return nil, err
	}

	if output.AuthenticationResult == nil {
		return nil, fmt.Errorf("authentication failed: no result returned")
	}

	return &model.AuthResponse{
		AccessToken:  aws.ToString(output.AuthenticationResult.AccessToken),
		RefreshToken: aws.ToString(output.AuthenticationResult.RefreshToken),
		IdToken:      aws.ToString(output.AuthenticationResult.IdToken),
		ExpiresIn:    output.AuthenticationResult.ExpiresIn,
		TokenType:    aws.ToString(output.AuthenticationResult.TokenType),
	}, nil
}

func (p *CognitoAuthProvider) ConfirmSignUp(ctx context.Context, email, confirmationCode string) error {
	_, err := p.client.ConfirmSignUp(ctx, &cognitoidentityprovider.ConfirmSignUpInput{
		ClientId:         aws.String(p.clientID),
		Username:         aws.String(email),
		ConfirmationCode: aws.String(confirmationCode),
	})
	return err
}
