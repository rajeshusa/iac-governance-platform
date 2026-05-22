# terraform/modules/ec2/outputs.tf

output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.main.name
}

output "launch_template_id" {
  description = "ID of the Launch Template"
  value       = aws_launch_template.main.id
}

output "security_group_id" {
  description = "ID of the instance security group"
  value       = aws_security_group.instance.id
}

output "instance_role_arn" {
  description = "ARN of the IAM instance role"
  value       = aws_iam_role.instance.arn
}

output "instance_role_name" {
  description = "Name of the IAM instance role"
  value       = aws_iam_role.instance.name
}

output "instance_profile_arn" {
  description = "ARN of the IAM instance profile"
  value       = aws_iam_instance_profile.instance.arn
}
