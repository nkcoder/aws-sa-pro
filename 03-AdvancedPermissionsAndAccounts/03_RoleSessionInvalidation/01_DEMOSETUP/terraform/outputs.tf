output "vpc_id" {
  description = "ID of the A4L VPC"
  value       = aws_vpc.a4l.id
}

output "instance_public_ips" {
  description = "Public IPv4 addresses of the hosting instances"
  value       = { for k, i in aws_instance.hosting : i.tags.Name => i.public_ip }
}

output "instance_role_arn" {
  description = "ARN of the shared EC2 instance role (target of the session-invalidation demo)"
  value       = aws_iam_role.instance.arn
}
