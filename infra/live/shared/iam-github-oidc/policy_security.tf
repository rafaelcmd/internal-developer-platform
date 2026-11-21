# CI role for the security component (live/shared/security).
# The account's IAM Access Analyzer analyzers, its CloudTrail trail and the S3
# bucket the trail delivers to, and the IAM account password policy.
#
# CloudTrail, Access Analyzer and the bucket are scoped by the project name
# prefix rather than by tag. The role may create and reconfigure the trail but
# is granted no object deletes, so it cannot remove log files already
# delivered.

resource "aws_iam_policy" "pipeline_security" {
  name        = "${var.project}-${var.environment}-pipeline-security-policy"
  description = "Pipeline policy for the security stack (Access Analyzer, CloudTrail, password policy)"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadServicesInStack"
        Effect = "Allow"
        Action = [
          "access-analyzer:GetAnalyzer",
          "access-analyzer:ListAnalyzers",
          "access-analyzer:ListTagsForResource",
          "cloudtrail:DescribeTrails",
          "cloudtrail:GetEventSelectors",
          "cloudtrail:GetInsightSelectors",
          "cloudtrail:GetTrail",
          "cloudtrail:GetTrailStatus",
          "cloudtrail:ListTags",
          "cloudtrail:ListTrails"
        ]
        Resource = "*"
      },
      {
        Sid    = "AccessAnalyzerManageProjectAnalyzers"
        Effect = "Allow"
        Action = [
          "access-analyzer:CreateAnalyzer",
          "access-analyzer:DeleteAnalyzer",
          "access-analyzer:UpdateAnalyzer",
          "access-analyzer:TagResource",
          "access-analyzer:UntagResource"
        ]
        Resource = "arn:aws:access-analyzer:*:${local.account_id}:analyzer/${var.project}-*"
      },
      {
        # CreateAnalyzer creates this service-linked role on first use. The
        # condition keeps the grant from creating any other service's role.
        Sid      = "AccessAnalyzerServiceLinkedRole"
        Effect   = "Allow"
        Action   = "iam:CreateServiceLinkedRole"
        Resource = "arn:aws:iam::${local.account_id}:role/aws-service-role/access-analyzer.amazonaws.com/AWSServiceRoleForAccessAnalyzer"
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = "access-analyzer.amazonaws.com"
          }
        }
      },
      {
        Sid    = "CloudTrailManageProjectTrail"
        Effect = "Allow"
        Action = [
          "cloudtrail:CreateTrail",
          "cloudtrail:DeleteTrail",
          "cloudtrail:UpdateTrail",
          "cloudtrail:StartLogging",
          "cloudtrail:StopLogging",
          "cloudtrail:PutEventSelectors",
          "cloudtrail:AddTags",
          "cloudtrail:RemoveTags"
        ]
        Resource = "arn:aws:cloudtrail:*:${local.account_id}:trail/${var.project}-*"
      },
      {
        # Bucket configuration only. Object reads and deletes are absent, so the
        # pipeline can neither read the audit record nor erase it.
        Sid    = "S3ManageTrailBucket"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:DeleteBucketPolicy",
          "s3:GetAccelerateConfiguration",
          "s3:GetBucket*",
          "s3:GetEncryptionConfiguration",
          "s3:GetLifecycleConfiguration",
          "s3:GetReplicationConfiguration",
          "s3:ListBucket",
          "s3:PutBucketOwnershipControls",
          "s3:PutBucketPolicy",
          "s3:PutBucketPublicAccessBlock",
          "s3:PutBucketTagging",
          "s3:PutBucketVersioning",
          "s3:PutEncryptionConfiguration",
          "s3:PutLifecycleConfiguration"
        ]
        Resource = "arn:aws:s3:::${var.project}-cloudtrail-*"
      },
      {
        # The password policy is a singleton on the account and takes no
        # resource ARN.
        Sid    = "IAMAccountPasswordPolicy"
        Effect = "Allow"
        Action = [
          "iam:UpdateAccountPasswordPolicy",
          "iam:DeleteAccountPasswordPolicy"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.tags
}
