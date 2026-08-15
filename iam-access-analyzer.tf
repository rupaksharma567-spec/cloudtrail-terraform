# ---------------------------------------------------------------------------
# IAM ACCESS ANALYZER -- External access detection (completely free)
# ---------------------------------------------------------------------------
# Cost note: This creates an "External Access" analyzer, which is free of
# charge. It scans resource-based policies (S3 buckets, IAM role trust
# policies, KMS keys, etc.) and flags anything accessible from outside your
# AWS account/zone of trust.
#
# We intentionally do NOT create an "Unused Access" analyzer here -- that
# analyzer type is billed per IAM role/user analyzed per month and isn't
# needed for this project's scope.

resource "aws_accessanalyzer_analyzer" "external_access" {
  analyzer_name = "external-access-analyzer"
  type          = "ACCOUNT"

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

output "access_analyzer_arn" {
  description = "IAM Access Analyzer ARN"
  value       = aws_accessanalyzer_analyzer.external_access.arn
}
