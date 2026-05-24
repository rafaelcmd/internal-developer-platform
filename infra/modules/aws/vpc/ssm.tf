# =============================================================================
# SSM Parameter Store publishing
# Publishes VPC identifiers under /idp/shared/vpc/* so downstream stacks can
# consume them via data.aws_ssm_parameter instead of terraform_remote_state.
# Decouples workspaces and avoids TFC state-access requirements.
# =============================================================================

locals {
  ssm_prefix = "/idp/shared/vpc"
}

resource "aws_ssm_parameter" "vpc_id" {
  name        = "${local.ssm_prefix}/id"
  description = "VPC ID published by the shared/vpc workspace"
  type        = "String"
  value       = aws_vpc.this.id

  tags = merge(var.tags, local.common_tags)
}

resource "aws_ssm_parameter" "vpc_cidr_block" {
  name        = "${local.ssm_prefix}/cidr_block"
  description = "Primary CIDR block of the shared VPC"
  type        = "String"
  value       = aws_vpc.this.cidr_block

  tags = merge(var.tags, local.common_tags)
}

resource "aws_ssm_parameter" "public_subnet_ids" {
  name        = "${local.ssm_prefix}/public_subnet_ids"
  description = "Comma-separated IDs of public subnets in the shared VPC"
  type        = "StringList"
  value       = join(",", [for s in aws_subnet.public : s.id])

  tags = merge(var.tags, local.common_tags)
}

resource "aws_ssm_parameter" "private_subnet_ids" {
  name        = "${local.ssm_prefix}/private_subnet_ids"
  description = "Comma-separated IDs of private subnets in the shared VPC"
  type        = "StringList"
  value       = join(",", [for s in aws_subnet.private : s.id])

  tags = merge(var.tags, local.common_tags)
}
