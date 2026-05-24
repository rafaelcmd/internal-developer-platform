# =============================================================================
# CoreDNS Fargate compatibility
# The default EKS CoreDNS deployment carries the annotation
# eks.amazonaws.com/compute-type: ec2, which prevents the Fargate scheduler
# from picking the pods up. Removing the annotation lets CoreDNS schedule on
# Fargate so cluster DNS works end-to-end.
# =============================================================================

resource "kubernetes_annotations" "coredns_remove_ec2_compute_type" {
  api_version = "apps/v1"
  kind        = "Deployment"

  metadata {
    name      = "coredns"
    namespace = "kube-system"
  }

  template_annotations = {
    "eks.amazonaws.com/compute-type" = null
  }

  force = true

  depends_on = [
    aws_eks_fargate_profile.this,
  ]
}
