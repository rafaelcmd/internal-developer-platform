package task

import (
	"strings"
	"testing"
)

// validBody is the message the ProvisionInfra state sends, field for field.
const validBody = `{
	"Task": "ProvisionInfra",
	"TaskToken": "token-123",
	"Input": {
		"RequestId": "req-1",
		"ApplicationName": "orders",
		"Resources": [
			{"name": "orders-db", "resource_type": "rds", "cloud_provider": "AWS", "specification": {"engine": "postgres"}},
			{"name": "orders-bucket", "resource_type": "gcs", "cloud_provider": "GCP"}
		]
	}
}`

func TestParseValidMessage(t *testing.T) {
	message, err := Parse([]byte(validBody))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}

	if message.Input.RequestID != "req-1" || message.Input.ApplicationName != "orders" {
		t.Errorf("unexpected input: %+v", message.Input)
	}
	if len(message.Input.Resources) != 2 {
		t.Fatalf("got %d resources, want 2", len(message.Input.Resources))
	}
	if got := message.Input.Resources[0].Specification["engine"]; got != "postgres" {
		t.Errorf("specification engine = %q, want postgres", got)
	}
}

func TestParseRejects(t *testing.T) {
	cases := map[string]struct {
		body string
		want string
	}{
		"malformed json": {`{`, "decode task message"},
		"other task":     {`{"Task": "CreateRepository"}`, `unsupported task "CreateRepository"`},
		"missing fields": {`{"Task": "ProvisionInfra", "Input": {}}`, "TaskToken, Input.RequestId, Input.ApplicationName"},
	}

	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			_, err := Parse([]byte(c.body))
			if err == nil || !strings.Contains(err.Error(), c.want) {
				t.Errorf("Parse error = %v, want it to contain %q", err, c.want)
			}
		})
	}
}

func TestPartitionByProvider(t *testing.T) {
	message, err := Parse([]byte(validBody))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}

	owned, foreign := message.Input.Partition()

	if len(owned) != 1 || owned[0].Name != "orders-db" {
		t.Errorf("owned = %+v, want only orders-db", owned)
	}
	if len(foreign) != 1 || foreign[0].Name != "orders-bucket" {
		t.Errorf("foreign = %+v, want only orders-bucket", foreign)
	}
}
