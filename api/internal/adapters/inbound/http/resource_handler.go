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

// Provision godoc
// @Summary Submit a resource provisioning request
// @Description Submits a new resource provisioning request to be processed asynchronously. The request is validated and queued for processing via SQS.
// @Tags resources
// @Accept json
// @Produce json
// @Param resource body model.Resource true "Resource provisioning request"
// @Success 202 {object} APIResponse[AcceptedResponse] "Request accepted for processing"
// @Failure 400 {object} ErrorResponse "Validation error"
// @Failure 500 {object} ErrorResponse "Failed to process request"
// @Router /v1/provision [post]
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
