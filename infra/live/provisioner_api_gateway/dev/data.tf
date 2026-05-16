# =============================================================================
# NLB LOOKUP
# The NLB is provisioned by the AWS Load Balancer Controller in response to the
# k8s Service in /k8s/api/service.yaml. This stack runs AFTER `kubectl apply`,
# so the NLB must already exist in AWS by name before `terraform apply` here.
#
# Required annotation on the Service:
#   service.beta.kubernetes.io/aws-load-balancer-name: ${var.nlb_name}
# =============================================================================

data "aws_lb" "api" {
  name = var.nlb_name
}
