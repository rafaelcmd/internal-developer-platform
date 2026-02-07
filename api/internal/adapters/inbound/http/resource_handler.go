package http

import (
	"net/http"

	"github.com/rafaelcmd/internal-developer-platform/api/internal/domain/model"
	"github.com/rafaelcmd/internal-developer-platform/api/internal/domain/ports/inbound"
)

type ResourceHandler struct {
	resourceService inbound.ResourceService
}

func NewResourceHandler(resourceService inbound.ResourceService) *ResourceHandler {
	return &ResourceHandler{
		resourceService: resourceService,
	}
}

// Provision handles submitting a resource provisioning request for async processing.
func (h *ResourceHandler) Provision(w http.ResponseWriter, r *http.Request) {
	requestID := getRequestID(r)

	// Decode and validate request body
	resource := DecodeAndValidate[model.Resource](w, r, requestID)
	if resource == nil {
		return // Response already sent by DecodeAndValidate
	}

	err := h.resourceService.SendProvisioningRequest(r.Context(), *resource)
	if err != nil {
		RespondWithError(w, http.StatusInternalServerError, ErrorResponse{
			Code:      ErrCodeInternalError,
			Message:   "Failed to process provisioning request",
			RequestID: requestID,
		})
		return
	}

	RespondWithJSON(w, http.StatusAccepted, NewAPIResponse(AcceptedResponse{
		Message:   "Request accepted for processing",
		RequestID: requestID,
		Status:    "ACCEPTED",
	}, requestID))
}
