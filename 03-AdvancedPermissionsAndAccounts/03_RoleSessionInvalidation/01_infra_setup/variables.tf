variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-southeast-2"
}

variable "instance_type" {
  description = "EC2 instance type for the A4L hosting instances"
  type        = string
  default     = "t2.micro"
}

# Resolves to the latest Amazon Linux 2023 AMI (upgraded from the CFN AL2 default).
variable "ami_ssm_parameter" {
  description = "SSM public parameter that resolves to the AMI ID"
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# Applied to every resource via the provider default_tags block.
variable "common_tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default = {
    Project   = "A4L-RoleSessionInvalidation"
    ManagedBy = "Terraform"
  }
}
