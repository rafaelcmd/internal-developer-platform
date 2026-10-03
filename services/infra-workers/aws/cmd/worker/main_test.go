package main

import (
	"bytes"
	"log/slog"
	"os"
	"strings"
	"testing"
)

func TestHandleLogsSampleTask(t *testing.T) {
	body, err := os.ReadFile("../../testdata/provision-infra.json")
	if err != nil {
		t.Fatalf("read sample: %v", err)
	}

	var out bytes.Buffer
	if err := handle(slog.New(slog.NewJSONHandler(&out, nil)), body); err != nil {
		t.Fatalf("handle: %v", err)
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

func TestHandleRejectsUnparseableMessage(t *testing.T) {
	var out bytes.Buffer
	if err := handle(slog.New(slog.NewJSONHandler(&out, nil)), []byte(`not json`)); err == nil {
		t.Fatal("handle returned nil for an unparseable message")
	}
}
