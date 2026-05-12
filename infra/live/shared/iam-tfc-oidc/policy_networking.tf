resource "aws_iam_policy" "provisioner_api_networking_policy" {
  name        = "${var.project}-${var.environment}-provisioner-api-networking-policy"
  description = "Least privilege policy for managing Networking resources (Service Discovery, Route 53)"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Service Discovery (Cloud Map) Statements
      {
        Sid    = "ServiceDiscoveryRead"
        Effect = "Allow"
        Action = [
          "servicediscovery:Get*",
          "servicediscovery:List*"
        ]
        Resource = "*"
      },
      {
        Sid    = "ServiceDiscoveryCreateTagged"
        Effect = "Allow"
        Action = [
          "servicediscovery:CreatePrivateDnsNamespace",
          "servicediscovery:CreateService",
          "servicediscovery:TagResource"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/Project" = var.project
          }
        }
      },
      {
        Sid    = "ServiceDiscoveryManageProjectResources"
        Effect = "Allow"
        Action = [
          "servicediscovery:DeleteNamespace",
          "servicediscovery:DeleteService",
          "servicediscovery:UpdateService",
          "servicediscovery:UntagResource",
          "servicediscovery:RegisterInstance",
          "servicediscovery:DeregisterInstance"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Project" = var.project
          }
        }
      },
      # Route 53 — CreatePrivateDnsNamespace provisions a private hosted zone under the hood
      {
        Sid    = "Route53PrivateHostedZoneForCloudMap"
        Effect = "Allow"
        Action = [
          "route53:CreateHostedZone",
          "route53:DeleteHostedZone",
          "route53:GetHostedZone",
          "route53:ListHostedZones",
          "route53:ListHostedZonesByName",
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets",
          "route53:AssociateVPCWithHostedZone",
          "route53:DisassociateVPCFromHostedZone",
          "route53:ChangeTagsForResource",
          "route53:ListTagsForResource",
          "route53:GetChange"
        ]
        Resource = "*"
      }
    ]
  })
}
