output "cloudtrail_arn" {
  description = "CloudTrail trail ka ARN"
  value       = aws_cloudtrail.audit_trail.arn
}

output "cloudtrail_logs_bucket" {
  description = "S3 bucket jahan CloudTrail logs store hote hain"
  value       = aws_s3_bucket.cloudtrail_logs.id
}

output "aws_account_id" {
  description = "Current AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}
