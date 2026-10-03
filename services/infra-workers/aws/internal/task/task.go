// Package task defines the message the scaffold state machine sends to an infra
// worker and the AWS worker's view of it.
//
// The shape is set by the ProvisionInfra state in
// infra/live/provisioner/dev/state_machine.tf, not by a Go type in another
// module. The envelope fields are PascalCase because the state machine writes
// them; the resources are passed through from the API's request unchanged, so
// they keep its snake_case. Change this file and that state together.
package task

import (
	"encoding/json"
	"fmt"
	"strings"
)

// Provider is the cloud_provider value this worker owns. It must match the
// value the API accepts for AWS.
const Provider = "AWS"

// ProvisionInfraTask is the name the state machine puts in Message.Task.
const ProvisionInfraTask = "ProvisionInfra"

// Message is a Step Functions .waitForTaskToken task delivered over SQS.
type Message struct {
	Task string `json:"Task"`

	// TaskToken is what the worker returns with SendTaskSuccess or
	// SendTaskFailure. Anyone holding it can complete the task, so it is never
	// logged.
	TaskToken string `json:"TaskToken"`

	Input Input `json:"Input"`
}

// Input is the infrastructure half of a provision request.
type Input struct {
	RequestID       string     `json:"RequestId"`
	ApplicationName string     `json:"ApplicationName"`
	Resources       []Resource `json:"Resources"`
}

// Resource is a single cloud resource, as the API published it.
type Resource struct {
	Name          string            `json:"name"`
	ResourceType  string            `json:"resource_type"`
	CloudProvider string            `json:"cloud_provider"`
	Specification map[string]string `json:"specification,omitempty"`
}

// Parse decodes a queue message and verifies the fields the worker depends on.
func Parse(body []byte) (Message, error) {
	var message Message

	if err := json.Unmarshal(body, &message); err != nil {
		return Message{}, fmt.Errorf("decode task message: %w", err)
	}

	if message.Task != ProvisionInfraTask {
		return Message{}, fmt.Errorf("unsupported task %q", message.Task)
	}

	var missing []string

	if strings.TrimSpace(message.TaskToken) == "" {
		missing = append(missing, "TaskToken")
	}
	if strings.TrimSpace(message.Input.RequestID) == "" {
		missing = append(missing, "Input.RequestId")
	}
	if strings.TrimSpace(message.Input.ApplicationName) == "" {
		missing = append(missing, "Input.ApplicationName")
	}

	if len(missing) > 0 {
		return Message{}, fmt.Errorf("task message is missing %s", strings.Join(missing, ", "))
	}

	return message, nil
}

// Partition separates the resources this worker owns from those that belong to
// another provider's worker.
//
// The control plane is responsible for routing each resource to its provider's
// worker, so a non-empty foreign slice means that routing is wrong. The worker
// reports it rather than provisioning resources in a cloud it does not own.
func (i Input) Partition() (owned, foreign []Resource) {
	for _, resource := range i.Resources {
		if resource.CloudProvider == Provider {
			owned = append(owned, resource)
		} else {
			foreign = append(foreign, resource)
		}
	}
	return owned, foreign
}
