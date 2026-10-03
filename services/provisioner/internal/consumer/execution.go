package consumer

import (
	"context"
	"errors"
	"fmt"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/sfn"
	"github.com/aws/aws-sdk-go-v2/service/sfn/types"
)

// ExecutionStarter starts the scaffold state machine for one provision request.
// Narrowed to an interface so Dispatch can be tested without AWS, and so the
// Kafka path, which never touches AWS, can run without one.
type ExecutionStarter interface {
	// Start begins an execution named name with input as its execution input.
	// Starting an execution that already exists under that name is not an
	// error: it is how a redelivered message is recognised.
	Start(ctx context.Context, name string, input []byte) (Started, error)
}

// Started describes the outcome of a Start call.
type Started struct {
	// ExecutionArn is empty when the execution already existed, because
	// ExecutionAlreadyExists does not return the ARN of the existing one.
	ExecutionArn string

	// AlreadyStarted reports that an execution under this name was started by
	// an earlier delivery of the same message.
	AlreadyStarted bool
}

// SFNClient is the part of the Step Functions API the starter uses.
// *sfn.Client satisfies it.
type SFNClient interface {
	StartExecution(context.Context, *sfn.StartExecutionInput, ...func(*sfn.Options)) (*sfn.StartExecutionOutput, error)
}

// StepFunctionsStarter starts executions of one state machine.
type StepFunctionsStarter struct {
	Client          SFNClient
	StateMachineArn string
}

// Start calls StartExecution with a deterministic name, so SQS redelivering a
// message the consumer already acted on collides with the first execution
// instead of starting a second one.
func (s StepFunctionsStarter) Start(ctx context.Context, name string, input []byte) (Started, error) {
	output, err := s.Client.StartExecution(ctx, &sfn.StartExecutionInput{
		StateMachineArn: aws.String(s.StateMachineArn),
		Name:            aws.String(name),
		Input:           aws.String(string(input)),
	})

	var exists *types.ExecutionAlreadyExists
	if errors.As(err, &exists) {
		return Started{AlreadyStarted: true}, nil
	}
	if err != nil {
		return Started{}, fmt.Errorf("start execution %s: %w", name, err)
	}

	return Started{ExecutionArn: aws.ToString(output.ExecutionArn)}, nil
}
