# ---------------------------------------------------------------------------
# AUTOMATED INCIDENT RESPONSE -- EventBridge + Lambda + SNS
# ---------------------------------------------------------------------------
# Cost note: EventBridge rules matching AWS service events are free. Lambda's
# free tier (1M requests/month) comfortably covers this low-traffic account.
# SNS free tier includes 1,000 email notifications/month. This phase should
# stay effectively free for a personal lab.
#
# Design: Security Hub already aggregates findings from GuardDuty, IAM
# Access Analyzer, and AWS Config (see security-hub.tf). Instead of wiring
# separate automation per source service, this listens to Security Hub
# itself -- one rule covers findings from all three sources.
#
# Severity filter: MEDIUM and above. Filtering out INFORMATIONAL/LOW keeps
# this from notifying on routine noise, while staying loose enough to
# realistically trigger during normal testing (unlike a HIGH/CRITICAL-only
# filter, which might rarely fire on a low-traffic personal account).
#
# Response action: sends a formatted email via SNS. This intentionally
# stops at notification, not automated remediation (e.g. auto-isolating an
# instance or revoking credentials) -- taking destructive/corrective action
# automatically carries real risk of misfiring on a learning account. The
# same EventBridge -> Lambda pattern here is what a remediation action would
# build on top of.

# NOTE: The `archive` provider requirement must be added to your existing
# main.tf's `required_providers` block instead of declared here -- Terraform
# only allows one required_providers block per module, and main.tf already
# has one (for the aws provider). Add this to it:
#
#   archive = {
#     source  = "hashicorp/archive"
#     version = "~> 2.4"
#   }

variable "notification_email" {
  description = "Email address to receive security finding notifications. Set this in a terraform.tfvars file (already gitignored) -- do not hardcode a real email in this file since it's committed to a public repo."
  type        = string
}

# ---------------------------------------------------------------------------
# SNS -- notification topic
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "security_alerts" {
  name = "security-hub-alerts"

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ---------------------------------------------------------------------------
# LAMBDA -- formats the finding and publishes to SNS
# ---------------------------------------------------------------------------

data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/security_finding_notifier.zip"

  source {
    filename = "index.py"
    content  = <<-PYTHON
      import json
      import os
      import boto3

      sns = boto3.client("sns")
      SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]


      def handler(event, context):
          detail = event.get("detail", {})
          findings = detail.get("findings", [])

          if not findings:
              print("No findings in event payload, nothing to notify.")
              return {"statusCode": 200, "body": "no findings"}

          for finding in findings:
              severity = finding.get("Severity", {}).get("Label", "UNKNOWN")
              title = finding.get("Title", "Untitled finding")
              description = finding.get("Description", "")
              resources = finding.get("Resources", [])
              resource_type = resources[0].get("Type", "Unknown") if resources else "Unknown"
              product = finding.get("ProductName", "Unknown source")

              message = (
                  f"Security Hub Finding\\n"
                  f"---------------------\\n"
                  f"Severity: {severity}\\n"
                  f"Source: {product}\\n"
                  f"Title: {title}\\n"
                  f"Resource type: {resource_type}\\n\\n"
                  f"Description:\\n{description}\\n"
              )

              sns.publish(
                  TopicArn=SNS_TOPIC_ARN,
                  Subject=f"[{severity}] {title}"[:100],
                  Message=message,
              )
              print(f"Published notification for finding: {title}")

          return {"statusCode": 200, "body": f"processed {len(findings)} finding(s)"}
    PYTHON
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "security-finding-notifier-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# Basic Lambda execution (CloudWatch Logs write access)
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Scoped permission to publish only to this specific SNS topic
resource "aws_iam_role_policy" "lambda_sns_publish" {
  name = "publish-to-security-alerts-topic"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.security_alerts.arn
      }
    ]
  })
}

resource "aws_lambda_function" "security_finding_notifier" {
  function_name    = "security-finding-notifier"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "index.handler"
  runtime          = "python3.13"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 15

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.security_alerts.arn
    }
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# ---------------------------------------------------------------------------
# EVENTBRIDGE -- triggers the Lambda on Security Hub findings (MEDIUM+)
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "security_hub_findings" {
  name        = "security-hub-medium-plus-findings"
  description = "Matches Security Hub findings with severity MEDIUM, HIGH, or CRITICAL"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = {
          Label = ["MEDIUM", "HIGH", "CRITICAL"]
        }
        Workflow = {
          Status = ["NEW"]
        }
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "invoke_lambda" {
  rule = aws_cloudwatch_event_rule.security_hub_findings.name
  arn  = aws_lambda_function.security_finding_notifier.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.security_finding_notifier.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.security_hub_findings.arn
}

output "sns_topic_arn" {
  description = "SNS topic ARN for security alerts"
  value       = aws_sns_topic.security_alerts.arn
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.security_finding_notifier.function_name
}
