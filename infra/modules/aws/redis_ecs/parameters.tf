resource "aws_ssm_parameter" "redis_endpoint" {
  name  = var.ssm_parameter_name
  type  = var.ssm_parameter_type
  value = local.redis_endpoint

  tags = local.common_tags
}
