# ---------------------------------------------------------------------------
# AWS CONFIG -- Resource compliance tracking (scoped to minimize cost)
# ---------------------------------------------------------------------------
# Cost note: Unlike CloudTrail/GuardDuty/Access Analyzer, AWS Config is NOT
# free -- it charges roughly $0.003 per configuration item recorded. To keep
# this low for a lab budget, recording is scoped to only IAM and S3 resource
# types (the ones most relevant to a security audit project) instead of
# "all supported resources" across the whole account.
#
# We also do NOT attach any Config Rules here -- managed/custom rule
# evaluations carry their own additional cost and aren't needed yet.

# Dedicated S3 bucket for Config snapshots (kept separate from the
# CloudTrail logs bucket to avoid touching that bucket's existing policy).
resource "aws_s3_bucket" "config_logs" {
  bucket = "cloud-security-config-logs-${data.aws_caller_identity.current.account_id}"

  tags = {
    Project     = var.project_name
    Environment = var.environment
    Purpose     = "aws-config-logs"
  }
}

resource "aws_s3_bucket_public_access_block" "config_logs" {
  bucket = aws_s3_bucket.config_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config_logs" {
  bucket = aws_s3_bucket.config_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "config_logs" {
  bucket = aws_s3_bucket.config_logs.id

  rule {
    id     = "config-log-lifecycle"
    status = "Enabled"

    filter {}

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    expiration {
      days = 90
    }
  }
}

data "aws_iam_policy_document" "config_bucket_policy" {
  statement {
    sid    = "AWSConfigBucketPermissionsCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.config_logs.arn]
  }

  statement {
    sid    = "AWSConfigBucketExistenceCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.config_logs.arn]
  }

  statement {
    sid    = "AWSConfigBucketDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.config_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "config_logs" {
  bucket = aws_s3_bucket.config_logs.id
  policy = data.aws_iam_policy_document.config_bucket_policy.json
}

# IAM role that lets the AWS Config service read resources and write to S3
resource "aws_iam_role" "config_role" {
  name = "aws-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "config_role_policy" {
  role       = aws_iam_role.config_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

# Configuration recorder -- scoped to IAM + S3 only (keeps configuration-item
# volume, and therefore cost, low)
resource "aws_config_configuration_recorder" "main" {
  name     = "security-audit-recorder"
  role_arn = aws_iam_role.config_role.arn

  recording_group {
    all_supported                 = false
    include_global_resource_types = false
    resource_types = [
      "AWS::IAM::User",
      "AWS::IAM::Role",
      "AWS::IAM::Policy",
      "AWS::S3::Bucket",
    ]
  }
}

resource "aws_config_delivery_channel" "main" {
  name           = "security-audit-delivery-channel"
  s3_bucket_name = aws_s3_bucket.config_logs.bucket

  depends_on = [aws_config_configuration_recorder.main]
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.main]
}

output "config_recorder_name" {
  description = "AWS Config recorder name"
  value       = aws_config_configuration_recorder.main.name
}

output "config_logs_bucket" {
  description = "S3 bucket for AWS Config snapshots"
  value       = aws_s3_bucket.config_logs.bucket
}
