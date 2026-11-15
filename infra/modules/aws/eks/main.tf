# The EKS control plane, its IAM role and security group, the access entries
# that grant operators and pipelines kubectl, and the IAM OIDC provider that makes IRSA
# possible. Every platform workload runs on this cluster.
#
# Compute is Fargate only; see fargate.tf. The add-ons the cluster needs to be
# usable are in the sibling files: coredns_fargate.tf, aws_lb_controller.tf,
# fargate_logging.tf, otel_collector.tf and datadog_cluster_agent.tf.

data "aws_caller_identity" "current" {}

# The source conditions stop EKS from assuming this role on behalf of a cluster
# in another account, or of another cluster in this one.
data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}"]
    }
  }
}

# Left at the root path with no boundary: EKS cannot change a cluster's role in
# place, so moving it would replace the cluster. The api pipeline can attach
# only AmazonEKSClusterPolicy to it and holds no inline-policy grant on it.
resource "aws_iam_role" "cluster" {
  name               = "${var.cluster_name}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# EKS creates a security group of its own. This one is attached in addition so
# that other security groups have a stable, Terraform-owned group to reference.
resource "aws_security_group" "cluster" {
  name        = "${var.cluster_name}-cluster-sg"
  description = "Additional security group for EKS control plane ENIs"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-cluster-sg"
  })
}

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  enabled_cluster_log_types = var.enabled_cluster_log_types

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.public_access_cidrs
  }

  # Access entries only. Every principal, including the Fargate pod execution
  # role, is authorized through an entry, so the aws-auth ConfigMap has no
  # effect. EKS cannot switch a cluster back to CONFIG_MAP once it is API.
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  tags = merge(local.common_tags, {
    Datadog       = "monitored"
    "datadog:env" = var.environment
  })

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_cloudwatch_log_group.cluster,
  ]
}

# Grants kubectl to additional IAM principals: operator workstations, the
# deploy role, and the CI role of any stack that manages Kubernetes objects.
# Without an entry, the kubernetes provider fails with a bare "Unauthorized" that
# says nothing about IAM. The cluster creator already has admin through
# bootstrap_cluster_creator_admin_permissions above.
locals {
  access_entries = { for entry in var.access_entries : entry.principal_arn => entry }
}

resource "aws_eks_access_entry" "this" {
  for_each = local.access_entries

  cluster_name      = aws_eks_cluster.this.name
  principal_arn     = each.key
  type              = "STANDARD"
  kubernetes_groups = each.value.kubernetes_groups

  tags = local.common_tags
}

resource "aws_eks_access_policy_association" "this" {
  for_each = local.access_entries

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.key
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/${each.value.access_policy}"

  access_scope {
    type       = length(each.value.namespaces) > 0 ? "namespace" : "cluster"
    namespaces = length(each.value.namespaces) > 0 ? each.value.namespaces : null
  }

  depends_on = [aws_eks_access_entry.this]
}

moved {
  from = aws_eks_access_entry.admins
  to   = aws_eks_access_entry.this
}

moved {
  from = aws_eks_access_policy_association.admins
  to   = aws_eks_access_policy_association.this
}

# Registers the cluster's OIDC issuer with IAM, which is the prerequisite for
# IRSA. modules/aws/irsa consumes the ARN and URL emitted here.
data "tls_certificate" "cluster_oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster_oidc.certificates[0].sha1_fingerprint]

  tags = local.common_tags
}
