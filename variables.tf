variable "aws_region" {
  description = "AWS region jahan CloudTrail resources banenge"
  type        = string
  default     = "us-east-1"
}

variable "trail_name" {
  description = "CloudTrail trail ka naam"
  type        = string
  default     = "cloud-security-audit-trail-tf"
}

variable "environment" {
  description = "Tagging ke liye environment label"
  type        = string
  default     = "lab"
}

variable "project_name" {
  description = "Tagging ke liye project label"
  type        = string
  default     = "cloud-security-lab"
}
