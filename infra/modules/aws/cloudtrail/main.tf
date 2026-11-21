# A multi-Region CloudTrail trail and the S3 bucket it delivers to. The trail
# is the account's record of every management API call, which is what an IAM
# investigation starts from: who assumed which role, and what that session did.
#
# The bucket accepts writes only from this trail and only over TLS, keeps every
# object version, and expires logs after var.log_retention_days. Log file
# validation lets a reader prove a delivered file was not altered afterwards.

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  # Built rather than read from aws_cloudtrail.this: the trail cannot be created
  # until the bucket policy allows it to write, and that policy names the trail.
  trail_arn = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${var.name}"
}

resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name

  # False so a destroy cannot take the audit record with it. A destroy of a
  # bucket that still holds logs fails until the objects are removed by hand.
  force_destroy = false

  tags = var.tags
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Noncurrent versions expire on the same schedule, or versioning would keep
# every overwritten or deleted log forever.
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.log_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.log_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# aws:SourceArn confines both CloudTrail statements to this trail, so another
# account's trail cannot deliver into the bucket.
data "aws_iam_policy_document" "bucket" {
  statement {
    sid       = "CloudTrailAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.this.arn]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  statement {
    sid       = "CloudTrailWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.this.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

# Applied after the public access block: S3 evaluates a new policy against the
# block, and the two calls racing can fail with AccessDenied.
resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket.json

  depends_on = [aws_s3_bucket_public_access_block.this]
}

# CloudTrail checks the bucket policy when the trail is created, so the trail
# must wait for it.
resource "aws_cloudtrail" "this" {
  name           = var.name
  s3_bucket_name = aws_s3_bucket.this.id

  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  tags = var.tags

  depends_on = [aws_s3_bucket_policy.this]
}
