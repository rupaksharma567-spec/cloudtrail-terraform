# ---------------------------------------------------------------------------
# NETWORK + APPLICATION LAYER -- VPC + EC2 (lab mode, SSM access only)
# ---------------------------------------------------------------------------
# Cost note: t3.micro is free-tier eligible (750 hrs/month for new accounts,
# first 12 months). Outside free tier, it costs roughly $0.01/hr (~$7-8/month
# if run 24/7) -- more than this project's $5 budget on its own. This is
# managed with a "lab mode" workflow: stop the instance via AWS CLI when not
# actively testing (stopped = $0 compute cost, only ~$0.60/month for the
# small EBS root volume). See the bottom of this file for stop/start commands.
#
# Design choice: access is via AWS Systems Manager (SSM) Session Manager,
# NOT SSH. This means the security group has ZERO inbound rules -- the
# instance is not reachable from the internet at all, only reachable by
# someone with AWS IAM permissions calling the SSM API. No SSH keys to
# manage, no port 22 exposed.
#
# No NAT Gateway or ALB here -- both carry real hourly costs that would
# blow the budget, and neither is needed for this lab setup (the instance
# sits in a public subnet with a direct internet route for the SSM agent
# to reach AWS endpoints).

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_vpc" "lab" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "security-lab-vpc"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name        = "security-lab-public-subnet"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name        = "security-lab-igw"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }

  tags = {
    Name        = "security-lab-public-rt"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security group with NO inbound rules -- instance is unreachable from the
# internet. Outbound is open so the SSM agent can reach AWS endpoints.
resource "aws_security_group" "lab_instance" {
  name        = "security-lab-instance-sg"
  description = "No inbound rules -- access via SSM Session Manager only"
  vpc_id      = aws_vpc.lab.id

  egress {
    description = "Allow all outbound (required for SSM agent to reach AWS endpoints)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "security-lab-instance-sg"
    Project     = var.project_name
    Environment = var.environment
  }
}

# IAM role that lets the instance be managed via SSM Session Manager
resource "aws_iam_role" "ec2_ssm_role" {
  name = "security-lab-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_policy" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm_profile" {
  name = "security-lab-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm_role.name
}

resource "aws_instance" "lab" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.lab_instance.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm_profile.name
  associate_public_ip_address = true

  tags = {
    Name        = "security-lab-instance"
    Project     = var.project_name
    Environment = var.environment
  }

  # AWS periodically releases newer Amazon Linux AMIs, and the
  # associate_public_ip_address attribute is a known Terraform/AWS provider
  # quirk -- AWS sometimes reads it back as false even when the instance
  # correctly has a public IP (via the subnet's map_public_ip_on_launch).
  # Ignoring both here prevents Terraform from destroying and recreating
  # this instance on every plan due to drift that isn't a real problem.
  lifecycle {
    ignore_changes = [ami, associate_public_ip_address]
  }
}

output "ec2_instance_id" {
  description = "EC2 instance ID -- use this to stop/start/connect"
  value       = aws_instance.lab.id
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.lab.id
}

# ---------------------------------------------------------------------------
# LAB MODE -- run these from PowerShell after terraform apply, NOT terraform
# commands. Stopping/starting via AWS CLI does not conflict with Terraform.
# ---------------------------------------------------------------------------
#
# Connect (requires Session Manager plugin -- see setup steps):
#   aws ssm start-session --target <instance-id-from-output>
#
# Stop when done testing (compute cost becomes $0):
#   aws ec2 stop-instances --instance-ids <instance-id>
#
# Start again when needed:
#   aws ec2 start-instances --instance-ids <instance-id>
