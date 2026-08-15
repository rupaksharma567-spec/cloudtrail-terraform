# Cloud Security Audit Trail — Terraform (IaC)

Terraform code jo CloudTrail + S3 audit logging setup ko infrastructure-as-code
mein deploy karta hai. Ye wahi setup hai jo pehle AWS Console se manually banaya
gaya tha — ab reusable aur version-controlled hai.

## Kya banega

- **S3 bucket** — CloudTrail logs ke liye, encrypted (SSE-S3), public access blocked, versioning on
- **Lifecycle rule** — 30 din baad Glacier, 90 din baad auto-expire (cost control)
- **Bucket policy** — sirf CloudTrail service ko write access
- **CloudTrail trail** — multi-region, Management events (Read + Write), log file validation enabled

## Prerequisites

1. [Terraform](https://developer.hashicorp.com/terraform/install) installed (v1.5+)
2. AWS CLI configured with credentials:
   ```
   aws configure
   ```
   (IAM user ka access key/secret use karo, root account ka nahi)

## Kaise chalayein

```bash
terraform init      # providers download honge
terraform plan       # dekho kya banega, bina apply kiye
terraform apply       # confirm karke resources create honge
```

Apply hone ke baad Terraform bucket name aur trail ARN print karega.

Sab hata na ho toh:

```bash
terraform destroy
```

## Important — existing manual resources ke saath conflict

Agar tumne pehle se console se `cloud-security-audit-trail` aur uska S3 bucket
bana rakha hai, toh ye code ek **naya, alag** bucket/trail banayega
(`cloud-security-audit-logs-<account-id>` naam se), taaki koi naming clash na ho.

Do options hain:
1. **Naya banao, purana delete karo** — is code se apply karo, phir console se
   purana wala manually delete kar do.
2. **Purane ko import karo** — existing resources ko Terraform state mein
   import karo (`terraform import`) taaki wahi resource ab IaC se managed ho.
   Option 1 simpler hai agar ye ek learning/portfolio project hai.

## Cost notes

- Management events ki first copy — **free** (AWS khud confirm karta hai)
- S3 storage — chhoti log volume ke liye negligible (~cents/month)
- Lifecycle rule ki wajah se logs 90 din baad auto-delete ho jaayenge
- KMS encryption jaan-bujh kar skip kiya hai (SSE-S3 use kiya) — cost bachane ke liye

## Portfolio ke liye

Is repo ko GitHub pe daalo with:
- Ye README
- Architecture diagram (screenshot ya draw.io)
- `terraform apply` ka output screenshot
- CloudTrail console verify screenshot (Logging = On)

Isse tumhara "I clicked buttons in console" project "I write infrastructure
as code" project ban jaata hai — recruiters isko differently dekhte hain.

## Screenshots

**Terraform apply — successful deployment**
![Terraform Apply](terraform-apply-success.png)

**CloudTrail verified in AWS Console**
![CloudTrail Console](cloudtrail-console-verify.png)

**S3 bucket security settings**
![S3 Security](s3-bucket-security.png)
