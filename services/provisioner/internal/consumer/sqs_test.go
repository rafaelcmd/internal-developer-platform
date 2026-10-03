package consumer

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/aws/aws-sdk-go-v2/service/sqs/types"
	"go.opentelemetry.io/otel"

	"github.com/rafaelcmd/internal-developer-platform/resource-provisioner-service/internal/logger"
)

// fakeSQS serves one batch of messages, then blocks until the context is
// cancelled — the same shape as a long poll against an empty queue, so RunSQS
// exits through its normal path rather than a panic.
type fakeSQS struct {
	messages []types.Message

	mu      sync.Mutex
	served  bool
	deleted []string
}

func (f *fakeSQS) ReceiveMessage(ctx context.Context, _ *sqs.ReceiveMessageInput, _ ...func(*sqs.Options)) (*sqs.ReceiveMessageOutput, error) {
	f.mu.Lock()
	first := !f.served
	f.served = true
	f.mu.Unlock()

	if first {
		return &sqs.ReceiveMessageOutput{Messages: f.messages}, nil
	}

	<-ctx.Done()
	return nil, ctx.Err()
}

func (f *fakeSQS) DeleteMessage(_ context.Context, in *sqs.DeleteMessageInput, _ ...func(*sqs.Options)) (*sqs.DeleteMessageOutput, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.deleted = append(f.deleted, aws.ToString(in.ReceiptHandle))
	return &sqs.DeleteMessageOutput{}, nil
}

func (f *fakeSQS) deletedHandles() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]string(nil), f.deleted...)
}

func runOnce(t *testing.T, client *fakeSQS, starter ExecutionStarter) {
	t.Helper()

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	done := make(chan struct{})
	go func() {
		defer close(done)
		_ = RunSQS(ctx, client, "https://sqs.test/queue", starter, otel.Tracer("test"), NewMetrics(otel.Meter("test")), logger.NopLogger{})
	}()

	// The batch is handled before the second receive blocks; cancelling then
	// lets RunSQS return.
	time.Sleep(200 * time.Millisecond)
	cancel()

	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("RunSQS did not return after the context was cancelled")
	}
}

const validRequest = `{"request_id":"11111111-1111-1111-1111-111111111111",` +
	`"application":{"name":"payments-api","template":"dotnet-consumer","owner":"team-payments"},` +
	`"requested_by":"rafael"}`

// A message the consumer cannot parse must stay on the queue. Deleting it
// discards the only copy of a request the caller was already told was accepted,
// and starves the dead-letter queue the redrive policy points at.
func TestRunSQS_LeavesUnparseableMessageOnTheQueue(t *testing.T) {
	client := &fakeSQS{messages: []types.Message{{
		Body:          aws.String("{ this is not a provision request"),
		ReceiptHandle: aws.String("receipt-bad"),
		MessageId:     aws.String("msg-bad"),
	}}}

	runOnce(t, client, &fakeStarter{})

	if got := client.deletedHandles(); len(got) != 0 {
		t.Fatalf("unparseable message was deleted (handles: %v); it must be left for redrive", got)
	}
}

func TestRunSQS_DeletesHandledMessage(t *testing.T) {
	client := &fakeSQS{messages: []types.Message{{
		Body:          aws.String(validRequest),
		ReceiptHandle: aws.String("receipt-good"),
		MessageId:     aws.String("msg-good"),
	}}}

	runOnce(t, client, &fakeStarter{})

	got := client.deletedHandles()
	if len(got) != 1 || got[0] != "receipt-good" {
		t.Fatalf("handled message should be deleted exactly once, got %v", got)
	}
}

// One bad message in a batch must not stop the good ones being acknowledged.
func TestRunSQS_MixedBatchDeletesOnlyTheHandledMessage(t *testing.T) {
	client := &fakeSQS{messages: []types.Message{
		{Body: aws.String("{ broken"), ReceiptHandle: aws.String("receipt-bad"), MessageId: aws.String("msg-bad")},
		{Body: aws.String(validRequest), ReceiptHandle: aws.String("receipt-good"), MessageId: aws.String("msg-good")},
	}}

	runOnce(t, client, &fakeStarter{})

	got := client.deletedHandles()
	if len(got) != 1 || got[0] != "receipt-good" {
		t.Fatalf("only the handled message should be deleted, got %v", got)
	}
}

// fakeStarter records the executions Dispatch asks for and returns err.
type fakeStarter struct {
	err error

	mu     sync.Mutex
	names  []string
	inputs []string
}

func (f *fakeStarter) Start(_ context.Context, name string, input []byte) (Started, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.names = append(f.names, name)
	f.inputs = append(f.inputs, string(input))
	if f.err != nil {
		return Started{}, f.err
	}
	return Started{ExecutionArn: "arn:aws:states:us-east-1:000000000000:execution:sm:" + name}, nil
}

// The execution is named after the request and receives the message body
// unchanged; both are what the state machine and its idempotency rely on.
func TestRunSQS_StartsExecutionNamedAfterTheRequest(t *testing.T) {
	client := &fakeSQS{messages: []types.Message{{
		Body:          aws.String(validRequest),
		ReceiptHandle: aws.String("receipt-good"),
		MessageId:     aws.String("msg-good"),
	}}}
	starter := &fakeStarter{}

	runOnce(t, client, starter)

	if len(starter.names) != 1 || starter.names[0] != "11111111-1111-1111-1111-111111111111" {
		t.Fatalf("execution names = %v, want the request id once", starter.names)
	}
	if starter.inputs[0] != validRequest {
		t.Fatalf("execution input was rewritten:\n got %s\nwant %s", starter.inputs[0], validRequest)
	}
}

// A request whose execution could not be started has not been handled, so it
// stays on the queue for redelivery.
func TestRunSQS_LeavesMessageWhenExecutionCannotStart(t *testing.T) {
	client := &fakeSQS{messages: []types.Message{{
		Body:          aws.String(validRequest),
		ReceiptHandle: aws.String("receipt-good"),
		MessageId:     aws.String("msg-good"),
	}}}

	runOnce(t, client, &fakeStarter{err: errors.New("throttled")})

	if got := client.deletedHandles(); len(got) != 0 {
		t.Fatalf("message was deleted although no execution started (handles: %v)", got)
	}
}
