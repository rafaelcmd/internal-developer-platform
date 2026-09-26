# Durable state for every provisioning request the platform accepts: which
# execution is carrying it, how far it got, and how it ended. The provisioner is
# the control plane and owns this; no other service reads it.
#
# It exists so that the answer to "what already happened to request X" survives
# the process that was working on it. Without it a provisioner crash between
# creating a repository and provisioning its infrastructure leaves nobody able
# to say which of the two happened.
#
# | Item            | PK                   | SK      |
# |-----------------|----------------------|---------|
# | Request state   | REQUEST#<request_id> | STATE   |

module "requests" {
  source = "../../../modules/aws/dynamodb"

  name      = "${local.name_prefix}-requests-${var.environment}"
  hash_key  = "PK"
  range_key = "SK"

  # Only key attributes are declared. DynamoDB rejects a table that declares an
  # attribute nothing keys on, so the status, timestamps and execution ARN the
  # state machine writes do not appear here.
  attributes = [
    { name = "PK", type = "S" },
    { name = "SK", type = "S" },
  ]

  # No TTL. A request record is the platform's audit trail of what it was asked
  # to build; the scaffolder's name reservations are the items that expire.

  point_in_time_recovery_enabled = var.point_in_time_recovery_enabled
  deletion_protection_enabled    = var.deletion_protection_enabled

  tags = local.tags
}
