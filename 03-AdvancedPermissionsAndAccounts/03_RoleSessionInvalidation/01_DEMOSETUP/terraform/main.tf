###############################################################################
# Terraform & Provider
###############################################################################

terraform {
  required_version = ">= 1.15"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.52"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = var.common_tags
  }
}

###############################################################################
# Network — VPC, IGW, route table, web subnets
###############################################################################

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "a4l" {
  cidr_block                       = "10.16.0.0/16"
  enable_dns_support               = true
  enable_dns_hostnames             = true
  assign_generated_ipv6_cidr_block = true

  tags = {
    Name = "a4l-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.a4l.id

  tags = {
    Name = "A4L-vpc1-igw"
  }
}

resource "aws_route_table" "web" {
  vpc_id = aws_vpc.a4l.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "A4L-vpc1-rt-web"
  }
}

# sn-web-A / B / C. The CloudFormation template carved /20 IPv4 blocks and
# /64 IPv6 blocks (subnet parts 0x03, 0x07, 0x0B of the VPC's /56) across the
# first three AZs. assign_ipv6_address_on_creation replaces the CFN IPv6
# workaround Lambda entirely.
locals {
  web_subnets = {
    A = { az_index = 0, cidr = "10.16.48.0/20", ipv6_netnum = 3 }
    B = { az_index = 1, cidr = "10.16.112.0/20", ipv6_netnum = 7 }
    C = { az_index = 2, cidr = "10.16.176.0/20", ipv6_netnum = 11 }
  }
}

resource "aws_subnet" "web" {
  for_each = local.web_subnets

  vpc_id                          = aws_vpc.a4l.id
  availability_zone               = data.aws_availability_zones.available.names[each.value.az_index]
  cidr_block                      = each.value.cidr
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.a4l.ipv6_cidr_block, 8, each.value.ipv6_netnum)
  map_public_ip_on_launch         = true
  assign_ipv6_address_on_creation = true

  tags = {
    Name = "sn-web-${each.key}"
  }
}

resource "aws_route_table_association" "web" {
  for_each = aws_subnet.web

  subnet_id      = each.value.id
  route_table_id = aws_route_table.web.id
}

###############################################################################
# Security Group — SSH/HTTP ingress, self-reference, egress
###############################################################################

resource "aws_security_group" "instance" {
  name_prefix = "a4l-default-instance-"
  description = "Enable SSH access via port 22 IPv4 & v6"
  vpc_id      = aws_vpc.a4l.id

  tags = {
    Name = "A4L-default-instance-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh_ipv4" {
  security_group_id = aws_security_group.instance.id
  description       = "Allow SSH IPv4 IN"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "http_ipv4" {
  security_group_id = aws_security_group.instance.id
  description       = "Allow HTTP IPv4 IN"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "ssh_ipv6" {
  security_group_id = aws_security_group.instance.id
  description       = "Allow SSH IPv6 IN"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv6         = "::/0"
}

# Self-reference: allow all TCP between members of this security group.
resource "aws_vpc_security_group_ingress_rule" "self_reference" {
  security_group_id            = aws_security_group.instance.id
  ip_protocol                  = "tcp"
  from_port                    = 0
  to_port                      = 65535
  referenced_security_group_id = aws_security_group.instance.id
}

# CloudFormation left AWS's default allow-all egress in place; Terraform strips
# it, so re-add it explicitly (instances need outbound for yum/wget).
resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  security_group_id = aws_security_group.instance.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "all_ipv6" {
  security_group_id = aws_security_group.instance.id
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
}

###############################################################################
# IAM — EC2 instance role, managed policies, instance profile
###############################################################################

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name_prefix        = "a4l-instance-"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "instance" {
  for_each = toset([
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess",
    "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess",
  ])

  role       = aws_iam_role.instance.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "instance" {
  name_prefix = "a4l-instance-"
  path        = "/"
  role        = aws_iam_role.instance.name
}

###############################################################################
# Compute — AMI lookup, CloudWatch config, hosting instances
###############################################################################

data "aws_ssm_parameter" "ami" {
  name = var.ami_ssm_parameter
}

resource "aws_ssm_parameter" "cloudwatch_config" {
  name        = "CloudWatchLinuxConfig-${aws_vpc.a4l.id}"
  description = "SSM Parameter for CloudWatchAgent Config"
  type        = "String"
  tier        = "Standard"
  value       = file("${path.module}/cloudwatch-agent-config.json")
}

locals {
  asset_base = "https://cl-sharedmedia.s3.amazonaws.com/sapro-iamrole-revocation"

  instances = {
    A = {
      name   = "A4L-HostingA"
      subnet = "A"
      asset_urls = [
        "${local.asset_base}/InstanceA/index.html",
        "${local.asset_base}/InstanceA/sophie.jpeg",
      ]
    }
    B = {
      name   = "A4L-HostingB"
      subnet = "B"
      asset_urls = [
        "${local.asset_base}/InstanceB/index.html",
        "${local.asset_base}/InstanceB/dogs1.jpg",
        "${local.asset_base}/InstanceB/dogs2.jpg",
        "${local.asset_base}/InstanceB/bones.png",
      ]
    }
  }
}

resource "aws_instance" "hosting" {
  for_each = local.instances

  ami                    = data.aws_ssm_parameter.ami.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.web[each.value.subnet].id
  vpc_security_group_ids = [aws_security_group.instance.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name

  user_data = templatefile("${path.module}/userdata.sh.tftpl", {
    cw_param_name = aws_ssm_parameter.cloudwatch_config.name
    asset_urls    = each.value.asset_urls
  })

  tags = {
    Name = each.value.name
  }
}
