locals {
  common_tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
  })

  # Bound in aws_lb_controller.tf and published as an output, because the
  # access entries in live/api/dev/dev.tfvars name it as a literal.
  target_group_binding_editor_group = "idp:target-group-binding-editors"
}
