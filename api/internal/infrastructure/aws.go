// Package infrastructure provides AWS infrastructure clients and utilities.
// This package isolates external infrastructure concerns from the business logic.
package infrastructure

import (
	"context"
	"fmt"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/cognitoidentityprovider"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/aws/aws-sdk-go-v2/service/ssm"
)

// AWSClients holds all AWS service clients.
type AWSClients struct {
	Config  aws.Config
	SSM     *ssm.Client
	SQS     *sqs.Client
	Cognito *cognitoidentityprovider.Client
}

// NewAWSClients creates and initializes all AWS clients.
func NewAWSClients(ctx context.Context, opts ...func(*config.LoadOptions) error) (*AWSClients, error) {
	cfg, err := config.LoadDefaultConfig(ctx, opts...)
	if err != nil {
		return nil, fmt.Errorf("failed to load AWS config: %w", err)
	}

	return &AWSClients{
		Config:  cfg,
		SSM:     ssm.NewFromConfig(cfg),
		SQS:     sqs.NewFromConfig(cfg),
		Cognito: cognitoidentityprovider.NewFromConfig(cfg),
	}, nil
}

// ParameterStore provides methods for fetching parameters from AWS SSM Parameter Store.
type ParameterStore struct {
	client *ssm.Client
}

// NewParameterStore creates a new ParameterStore.
func NewParameterStore(client *ssm.Client) *ParameterStore {
	return &ParameterStore{client: client}
}

// GetParameter retrieves a parameter value from Parameter Store.
func (p *ParameterStore) GetParameter(ctx context.Context, name string) (string, error) {
	result, err := p.client.GetParameter(ctx, &ssm.GetParameterInput{
		Name: aws.String(name),
	})
	if err != nil {
		return "", fmt.Errorf("failed to get parameter %s: %w", name, err)
	}

	if result.Parameter == nil || result.Parameter.Value == nil {
		return "", fmt.Errorf("parameter %s not found or empty", name)
	}

	return *result.Parameter.Value, nil
}

// GetSecureParameter retrieves a secure string parameter value from Parameter Store.
func (p *ParameterStore) GetSecureParameter(ctx context.Context, name string) (string, error) {
	result, err := p.client.GetParameter(ctx, &ssm.GetParameterInput{
		Name:           aws.String(name),
		WithDecryption: aws.Bool(true),
	})
	if err != nil {
		return "", fmt.Errorf("failed to get secure parameter %s: %w", name, err)
	}

	if result.Parameter == nil || result.Parameter.Value == nil {
		return "", fmt.Errorf("parameter %s not found or empty", name)
	}

	return *result.Parameter.Value, nil
}

// GetParameters retrieves multiple parameters from Parameter Store.
func (p *ParameterStore) GetParameters(ctx context.Context, names []string) (map[string]string, error) {
	if len(names) == 0 {
		return make(map[string]string), nil
	}

	// Convert string slice to []*string
	paramNames := make([]string, len(names))
	copy(paramNames, names)

	result, err := p.client.GetParameters(ctx, &ssm.GetParametersInput{
		Names: paramNames,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to get parameters: %w", err)
	}

	params := make(map[string]string)
	for _, param := range result.Parameters {
		if param.Name != nil && param.Value != nil {
			params[*param.Name] = *param.Value
		}
	}

	return params, nil
}
