# ---------------------------------------------------------------------------
# GUARDDUTY -- Threat detection (foundational only, no paid add-ons)
# ---------------------------------------------------------------------------
# Cost note: AWS gives a 30-day free trial for GuardDuty on first-time
# enablement in a region. After that, usage-based billing applies based on
# CloudTrail events / VPC Flow Logs / DNS logs analyzed. For a low-traffic
# personal/lab account with no EC2/VPC traffic, this typically stays very
# low -- but keep an eye on AWS Budget alerts after the trial period ends.
#
# We intentionally do NOT enable S3 Protection, Malware Protection, EKS
# Protection, or RDS Protection here -- these are separately-billed add-ons
# and not needed for foundational threat detection.

resource "aws_guardduty_detector" "main" {
  enable                       = true
  finding_publishing_frequency = "SIX_HOURS"

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

output "guardduty_detector_id" {
  description = "GuardDuty detector ID"
  value       = aws_guardduty_detector.main.id
}
