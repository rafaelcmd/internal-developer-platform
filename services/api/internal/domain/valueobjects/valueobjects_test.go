package valueobjects

import (
	"testing"
)

func TestNewEmail_Valid(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"test@example.com", "test@example.com"},
		{"TEST@EXAMPLE.COM", "test@example.com"},
		{"  user@domain.com  ", "user@domain.com"},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			email, err := NewEmail(tt.input)
			if err != nil {
				t.Errorf("NewEmail(%q) unexpected error: %v", tt.input, err)
			}
			if email.String() != tt.expected {
				t.Errorf("NewEmail(%q) = %q, want %q", tt.input, email.String(), tt.expected)
			}
		})
	}
}

func TestNewEmail_Invalid(t *testing.T) {
	tests := []string{
		"",
		"   ",
		"invalid",
		"@domain.com",
		"user@",
		"user@domain",
	}

	for _, tt := range tests {
		t.Run(tt, func(t *testing.T) {
			_, err := NewEmail(tt)
			if err == nil {
				t.Errorf("NewEmail(%q) expected error, got nil", tt)
			}
		})
	}
}

func TestNewCloudProvider_Valid(t *testing.T) {
	tests := []struct {
		input    string
		expected CloudProvider
	}{
		{"AWS", CloudProviderAWS},
		{"aws", CloudProviderAWS},
		{"Azure", CloudProviderAzure},
		{"AZURE", CloudProviderAzure},
		{"GCP", CloudProviderGCP},
		{"gcp", CloudProviderGCP},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			provider, err := NewCloudProvider(tt.input)
			if err != nil {
				t.Errorf("NewCloudProvider(%q) unexpected error: %v", tt.input, err)
			}
			if provider != tt.expected {
				t.Errorf("NewCloudProvider(%q) = %v, want %v", tt.input, provider, tt.expected)
			}
		})
	}
}

func TestNewCloudProvider_Invalid(t *testing.T) {
	tests := []string{
		"",
		"invalid",
		"ibm",
		"oracle",
	}

	for _, tt := range tests {
		t.Run(tt, func(t *testing.T) {
			_, err := NewCloudProvider(tt)
			if err == nil {
				t.Errorf("NewCloudProvider(%q) expected error, got nil", tt)
			}
		})
	}
}

func TestCloudProvider_IsValid(t *testing.T) {
	if !CloudProviderAWS.IsValid() {
		t.Error("CloudProviderAWS.IsValid() should return true")
	}
	if CloudProvider("invalid").IsValid() {
		t.Error("CloudProvider('invalid').IsValid() should return false")
	}
}

func TestNewResourceType_Valid(t *testing.T) {
	tests := []struct {
		input    string
		expected ResourceType
	}{
		{"VM", ResourceTypeVM},
		{"RDS", ResourceTypeRDS},
		{"S3", ResourceTypeS3},
		{"Lambda", ResourceTypeLambda},
		{"VPC", ResourceTypeVPC},
		{"ELB", ResourceTypeELB},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			rt, err := NewResourceType(tt.input)
			if err != nil {
				t.Errorf("NewResourceType(%q) unexpected error: %v", tt.input, err)
			}
			if rt != tt.expected {
				t.Errorf("NewResourceType(%q) = %v, want %v", tt.input, rt, tt.expected)
			}
		})
	}
}

func TestNewResourceType_Invalid(t *testing.T) {
	_, err := NewResourceType("invalid")
	if err == nil {
		t.Error("NewResourceType('invalid') expected error, got nil")
	}
}

func TestNewProvisioningStatus_Valid(t *testing.T) {
	tests := []struct {
		input    string
		expected ProvisioningStatus
	}{
		{"pending", StatusPending},
		{"PENDING", StatusPending},
		{"in_progress", StatusInProgress},
		{"completed", StatusCompleted},
		{"failed", StatusFailed},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			status, err := NewProvisioningStatus(tt.input)
			if err != nil {
				t.Errorf("NewProvisioningStatus(%q) unexpected error: %v", tt.input, err)
			}
			if status != tt.expected {
				t.Errorf("NewProvisioningStatus(%q) = %v, want %v", tt.input, status, tt.expected)
			}
		})
	}
}

func TestProvisioningStatus_IsFinal(t *testing.T) {
	if !StatusCompleted.IsFinal() {
		t.Error("StatusCompleted.IsFinal() should return true")
	}
	if !StatusFailed.IsFinal() {
		t.Error("StatusFailed.IsFinal() should return true")
	}
	if StatusPending.IsFinal() {
		t.Error("StatusPending.IsFinal() should return false")
	}
	if StatusInProgress.IsFinal() {
		t.Error("StatusInProgress.IsFinal() should return false")
	}
}

func TestNewResourceID_Valid(t *testing.T) {
	id, err := NewResourceID("resource-123")
	if err != nil {
		t.Errorf("NewResourceID unexpected error: %v", err)
	}
	if id.String() != "resource-123" {
		t.Errorf("ResourceID.String() = %q, want %q", id.String(), "resource-123")
	}
}

func TestNewResourceID_Invalid(t *testing.T) {
	_, err := NewResourceID("")
	if err == nil {
		t.Error("NewResourceID('') expected error, got nil")
	}

	_, err = NewResourceID("   ")
	if err == nil {
		t.Error("NewResourceID('   ') expected error, got nil")
	}
}

func TestNewSpecification_Valid(t *testing.T) {
	spec, err := NewSpecification("t2.micro")
	if err != nil {
		t.Errorf("NewSpecification unexpected error: %v", err)
	}
	if spec.String() != "t2.micro" {
		t.Errorf("Specification.String() = %q, want %q", spec.String(), "t2.micro")
	}
}

func TestNewSpecification_Invalid(t *testing.T) {
	_, err := NewSpecification("")
	if err == nil {
		t.Error("NewSpecification('') expected error, got nil")
	}
}
