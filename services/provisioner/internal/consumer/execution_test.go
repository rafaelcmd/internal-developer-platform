package consumer

import (
	"context"
	"errors"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/sfn"
	"github.com/aws/aws-sdk-go-v2/service/sfn/types"
)

type fakeSFN struct {
	err   error
	input *sfn.StartExecutionInput
}

func (f *fakeSFN) StartExecution(_ context.Context, in *sfn.StartExecutionInput, _ ...func(*sfn.Options)) (*sfn.StartExecutionOutput, error) {
	f.input = in
	if f.err != nil {
		return nil, f.err
	}
	return &sfn.StartExecutionOutput{ExecutionArn: aws.String("arn:execution")}, nil
}

func TestStepFunctionsStarter_StartsNamedExecution(t *testing.T) {
	client := &fakeSFN{}
	starter := StepFunctionsStarter{Client: client, StateMachineArn: "arn:sm"}

	started, err := starter.Start(context.Background(), "req-1", []byte(`{"request_id":"req-1"}`))
	if err != nil {
		t.Fatalf("Start: %v", err)
	}

	if started.ExecutionArn != "arn:execution" || started.AlreadyStarted {
		t.Errorf("started = %+v", started)
	}
	if aws.ToString(client.input.Name) != "req-1" || aws.ToString(client.input.StateMachineArn) != "arn:sm" {
		t.Errorf("StartExecution input = %+v", client.input)
	}
}

// A redelivered message must not fail: the execution it asks for is already
// running, which is the outcome the first delivery wanted.
func TestStepFunctionsStarter_TreatsExistingExecutionAsStarted(t *testing.T) {
	starter := StepFunctionsStarter{Client: &fakeSFN{err: &types.ExecutionAlreadyExists{}}}

	started, err := starter.Start(context.Background(), "req-1", nil)
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	if !started.AlreadyStarted {
		t.Errorf("started = %+v, want AlreadyStarted", started)
	}
}

func TestStepFunctionsStarter_ReturnsOtherErrors(t *testing.T) {
	starter := StepFunctionsStarter{Client: &fakeSFN{err: errors.New("throttled")}}

	if _, err := starter.Start(context.Background(), "req-1", nil); err == nil {
		t.Fatal("Start returned nil for a failed StartExecution")
	}
}
