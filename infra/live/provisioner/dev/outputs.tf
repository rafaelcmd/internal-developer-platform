output "irsa_role_arn" {
  description = "ARN of the IAM role the provisioner pod assumes"
  value       = module.irsa.role_arn
}

output "service_account_name" {
  description = "ServiceAccount the provisioner Deployment binds to (k8s/provisioner/deployment.yaml)"
  value       = module.irsa.service_account_name
}

output "scaffold_state_machine_arn" {
  description = "ARN of the scaffold state machine, which is what the provisioner's StartExecution takes"
  value       = module.state_machine.state_machine_arn
}

output "scaffold_state_machine_name" {
  description = "Name of the scaffold state machine"
  value       = module.state_machine.state_machine_name
}

output "scaffold_state_machine_role_arn" {
  description = "ARN of the role the state machine assumes to send tasks and write request state"
  value       = module.state_machine.role_arn
}

output "scaffold_state_machine_log_group_name" {
  description = "Log group execution history is delivered to"
  value       = module.state_machine.log_group_name
}

output "requests_table_name" {
  description = "Name of the request-state table, which is what the provisioner reads to answer what happened to a request"
  value       = module.requests.table_name
}

output "requests_table_arn" {
  description = "ARN of the request-state table"
  value       = module.requests.table_arn
}
