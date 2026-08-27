# Cloud Security Audit & Compliance Logging Platform — Terraform (IaC)

Terraform code that deploys a multi-layer AWS security monitoring stack as infrastructure-as-code. The setup was originally built manually through the AWS Console, then rebuilt in Terraform to be reusable and version-controlled.

## What this deploys

**1. CloudTrail — Audit logging**
- Multi-region trail, capturing Management events (Read + Write)
- Encrypted S3 bucket (SSE-S3), public access blocked, versioning enabled
- Log file validation enabled (tamper detection)
- Lifecycle rule — transitions to Glacier after 30 days, expires after 90 days

**2. GuardDuty — Threat detection**
- Foundational detector (CloudTrail/VPC/DNS-based threat analysis)
- No paid add-ons enabled (S3 Protection, Malware Protection, and EKS Protection are all intentionally skipped)

**3. IAM Access Analyzer — External exposure detection**
- Account-level external access analyzer
- Flags any resource (S3 bucket, IAM role, KMS key) that is unintentionally accessible from outside the account

**4. AWS Config — Resource configuration tracking**
- Scoped to IAM (Users/Roles/Policies) and S3 buckets only — not the entire account, to keep cost minimal
- Dedicated, encrypted S3 bucket for configuration snapshots
- No Config Rules attached (rule evaluations carry their own cost and weren't needed for this scope)

**5. Security Hub — Centralized findings aggregation**
- Aggregates findings from GuardDuty, IAM Access Analyzer, and AWS Config into a single dashboard
- No security standards subscribed (CIS, PCI-DSS, AWS Foundational Security Best Practices) — this avoids per-check costs entirely; only finding aggregation is enabled

**6. VPC + EC2 — Network layer (lab mode)**
- Public subnet with a t3.micro instance for hands-on testing
- Zero inbound security group rules — access is exclusively via AWS Systems Manager Session Manager (no SSH keys, no open ports)
- No NAT Gateway or Application Load Balancer (both carry real hourly costs not needed here)
- Run in "lab mode": stopped by default via AWS CLI, started only when actively testing, to keep compute cost near $0

## Architecture at a glance

```
AWS Account
    │
    ├── CloudTrail ──────────► S3 (audit logs)
    ├── GuardDuty ───────────► Threat findings ─┐
    ├── IAM Access Analyzer ─► Exposure findings ─┼──► Security Hub (aggregated view)
    ├── AWS Config ──────────► S3 (config snapshots) ─┘
    └── VPC (public subnet) ─► EC2 (t3.micro, SSM-only access)
```

## Prerequisites

1. [Terraform](https://developer.hashicorp.com/terraform/install) installed (v1.5+)
2. AWS CLI configured with credentials:
   ```
   aws configure
   ```
   (Use an IAM user's access key/secret — not the root account)

## How to run

```bash
terraform init      # downloads providers
terraform plan       # preview what will be created, without applying
terraform apply       # confirm and create the resources
```

After apply completes, Terraform prints all service outputs (bucket names, ARNs, detector IDs, instance ID).

To tear everything down:

```bash
terraform destroy
```

## Cost notes

| Service | Cost |
|---|---|
| CloudTrail | The first copy of management events is free |
| S3 (audit + config buckets) | Negligible for low log volume (~cents/month) |
| GuardDuty | 30-day free trial, then usage-based (very low for a low-traffic account) |
| IAM Access Analyzer | **Completely free** (external access analyzer type) |
| AWS Config | ~$0.003 per configuration item, scoped to IAM + S3 only to minimize cost |
| Security Hub | Aggregation only — no standards subscribed, so no per-check cost |
| EC2 (t3.micro) | Free-tier eligible; otherwise ~$0.01/hr — run in "lab mode" (stopped by default) to keep this near $0 |

Any resource that would meaningfully increase cost (RDS, NAT Gateway, Load Balancer) was intentionally left out.

## Real debugging encountered

During deployment, an `InsufficientS3BucketPolicyException` came up. Root cause: the CloudTrail resource had an extra `s3_key_prefix = "AWSLogs"` set, while AWS already automatically writes to an `AWSLogs/<account-id>/...` path by default. This created a mismatch between the actual write path and what the bucket policy allowed. Fix: removed the redundant `s3_key_prefix`, and the path matched correctly.

## Terraform Maintenance & Drift Management

Beyond the initial deployment, ongoing use of this project surfaced two real Terraform/AWS provider quirks — the kind of maintenance work that shows up *after* infrastructure is already running, not during first setup.

**Issue 1: AMI-driven instance replacement.** The EC2 instance's AMI is selected via a `data "aws_ami"` lookup with `most_recent = true`. When AWS released a newer Amazon Linux AMI, a routine `terraform plan` showed the instance as needing replacement — AWS has no in-place AMI swap, so this would have destroyed and recreated the instance every time a new AMI shipped.
*Fix:* added `lifecycle { ignore_changes = [ami] }` — new instances still launch on the latest AMI, but Terraform no longer treats a newer AMI as a reason to replace one that's already running.

**Issue 2: `associate_public_ip_address` drift.** A later `terraform plan` showed `associate_public_ip_address: false -> true # forces replacement`, despite the instance already having a working public IP (assigned via the subnet's `map_public_ip_on_launch`). This is a known AWS provider inconsistency — the attribute isn't always read back accurately for existing instances.
*Fix:* added `associate_public_ip_address` to the same `ignore_changes` list, eliminating a second unnecessary replacement cycle.

**Why this matters:** both issues were caught by reviewing `terraform plan` output *before* applying — neither change was blindly approved. Keeping a deployed environment stable over time, rather than just standing it up once, is a part of Infrastructure as Code that tutorials rarely cover.

## Live Detection Example — GuardDuty in Action

A few hours after deployment, GuardDuty generated its first real finding — proof that the threat detection layer isn't just configured, it's actively monitoring. The finding was triaged using the standard **Five Ws** framework:

**Finding:** `Policy:IAMUser/RootCredentialUsage` (Low severity, count: 263)

| | |
|---|---|
| **Who** | The AWS account root user — via temporary session credentials (STS), not a static root access key |
| **What** | Repeated calls to `ListManagedNotificationEvents` — a read-only API, no data-modifying or sensitive action involved |
| **When** | Observed continuously over a ~10-hour window — consistent with an active browser console session |
| **Where** | AWS Management Console, us-east-1 — source IP geolocated to the account owner's own known location |
| **Why** | Root was used to log into the console during initial account setup (MFA/billing configuration), which triggers GuardDuty's root-credential-usage policy check. The repeated calls were the browser's Notifications Center silently polling in the background while the console tab stayed open. |

**Response taken:**
- Verified the source IP/location matched the account owner's own activity — ruled out unauthorized access
- Confirmed no IAM, billing, or resource-modifying actions occurred under root — only read-only notification polling
- Reinforced existing practice: all day-to-day console/API work goes through the IAM user (with MFA); root is reserved strictly for account-level tasks, per AWS best practice

## Screenshots

**Terraform apply — successful deployment**
![Terraform Apply](terraform-apply-success.png)

**CloudTrail verified in AWS Console**
![CloudTrail Console](cloudtrail-console-verify.png)

**S3 bucket security settings**
![S3 Security](s3-bucket-security.png)

## For the portfolio

This turns "I clicked through the console" into "I write infrastructure as code, and I keep it stable" — recruiters read those very differently.
