# ---------------------------------------------------------------------------
# SECURITY HUB -- Centralized findings aggregation (minimal cost)
# ---------------------------------------------------------------------------
# Cost note: Security Hub charges for security checks run under subscribed
# standards (e.g. CIS, PCI-DSS, AWS Foundational Security Best Practices) and
# for findings ingested. We intentionally do NOT subscribe to any standards
# here (enable_default_standards = false) -- this avoids the per-check cost
# entirely. Security Hub still aggregates findings already being generated
# by GuardDuty, IAM Access Analyzer, and AWS Config into one dashboard, at
# minimal cost (finding ingestion only, a fraction of a cent per finding).

resource "aws_securityhub_account" "main" {
  enable_default_standards = false
}

output "security_hub_account_id" {
  description = "Security Hub account identifier"
  value       = aws_securityhub_account.main.id
}
