# =============================================================================
# VPC CORE OUTPUTS
# Outputs for VPC identification and reference
# =============================================================================

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

# =============================================================================
# SUBNET OUTPUTS
# Outputs for public and private subnet identification
# =============================================================================

output "public_subnet_ids" {
  description = "List of IDs of the public subnets"
  value       = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  description = "List of IDs of the private subnets"
  value       = [for s in aws_subnet.private : s.id]
}