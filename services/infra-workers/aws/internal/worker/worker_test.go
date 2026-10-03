package worker

import (
	"bytes"
	"context"
	"errors"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/sfn"
	sfntypes "github.com/aws/aws-sdk-go-v2/service/sfn/types"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/aws/aws-sdk-go-v2/service/sqs/types"
	"go.opentelemetry.io/otel"

	"github.com/rafaelcmd/internal-developer-platform/infra-worker-aws/internal/logger"
)

func sampleTask(t *testing.T) string {
	t.Helper()
	body, err := os.ReadFile("../../testdata/provision-infra.json")
	if err != nil {
		t.Fatalf("read sample: %v", err)
	}
	return string(body)
}

func bufferLogger(out *bytes.Buffer) logger.Logger {
	cfg := logger.DefaultConfig()
	cfg.Output = out
	return logger.New(cfg)
}

func TestHandleLogsResourcesWithoutTheToken(t *testing.T) {
	var out bytes.Buffer
	if _, err := Handle(context.Background(), bufferLogger(&out), []byte(sampleTask(t))); err != nil {
		t.Fatalf("Handle: %v", err)
	}

	logs := out.String()
	for _, want := range []string{`"resource_name":"orders-db"`, `"resource_count":2`, `"request_id":"`} {
		if !strings.Contains(logs, want) {
			t.Errorf("logs do not contain %s:\n%s", want, logs)
		}
	}
	if strings.Contains(logs, "example-task-token") {
		t.Errorf("logs contain the task token:\n%s", logs)
	}
}

// fakeSQS serves one batch, then blocks like a long poll on an empty queue.
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

type fakeSFN struct {
	err error

	mu      sync.Mutex
	outputs []string
	tokens  []string
}

func (f *fakeSFN) SendTaskSuccess(_ context.Context, in *sfn.SendTaskSuccessInput, _ ...func(*sfn.Options)) (*sfn.SendTaskSuccessOutput, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.tokens = append(f.tokens, aws.ToString(in.TaskToken))
	f.outputs = append(f.outputs, aws.ToString(in.Output))
	if f.err != nil {
		return nil, f.err
	}
	return &sfn.SendTaskSuccessOutput{}, nil
}

func runOnce(t *testing.T, body string, sfnClient *fakeSFN) *fakeSQS {
	t.Helper()

	client := &fakeSQS{messages: []types.Message{{Body: aws.String(body), ReceiptHandle: aws.String("receipt")}}}
	ctx, cancel := context.WithCancel(context.Background())

	done := make(chan struct{})
	go func() {
		defer close(done)
		_ = Worker{SQS: client, SFN: sfnClient, QueueURL: "https://sqs.test/q", Tracer: otel.Tracer("test"), Log: logger.NopLogger{}}.Run(ctx)
	}()

	time.Sleep(200 * time.Millisecond)
	cancel()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("Run did not return after the context was cancelled")
	}
	return client
}

func TestRunReportsSuccessThenDeletes(t *testing.T) {
	sfnClient := &fakeSFN{}
	client := runOnce(t, sampleTask(t), sfnClient)

	if len(sfnClient.tokens) != 1 || sfnClient.tokens[0] != "example-task-token" {
		t.Fatalf("SendTaskSuccess tokens = %v", sfnClient.tokens)
	}
	if want := `{"Provisioned":false,"Mode":"log-only","ResourceCount":2}`; sfnClient.outputs[0] != want {
		t.Errorf("output = %s, want %s", sfnClient.outputs[0], want)
	}
	if len(client.deleted) != 1 {
		t.Errorf("deleted = %v, want the message once", client.deleted)
	}
}

func TestRunLeavesTaskWhenSuccessCannotBeReported(t *testing.T) {
	client := runOnce(t, sampleTask(t), &fakeSFN{err: errors.New("throttled")})

	if len(client.deleted) != 0 {
		t.Errorf("deleted = %v, want the task left for redelivery", client.deleted)
	}
}

// A token Step Functions no longer holds cannot be answered by a redelivery
// either, so the task is dropped rather than cycled into the dead-letter queue.
func TestRunDropsTaskWithDeadToken(t *testing.T) {
	client := runOnce(t, sampleTask(t), &fakeSFN{err: &sfntypes.TaskTimedOut{}})

	if len(client.deleted) != 1 {
		t.Errorf("deleted = %v, want the task dropped", client.deleted)
	}
}

func TestRunLeavesUnparseableTask(t *testing.T) {
	sfnClient := &fakeSFN{}
	client := runOnce(t, "not json", sfnClient)

	if len(client.deleted) != 0 || len(sfnClient.tokens) != 0 {
		t.Errorf("deleted = %v, reported = %v; want neither", client.deleted, sfnClient.tokens)
	}
}
