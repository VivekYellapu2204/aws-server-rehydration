output "asg_name" {
  description = "Name of the Auto Scaling Group; mapped to ASG_NAME in CI/CD rollback stages"
  value       = aws_autoscaling_group.asg.name
}

output "asg_arn" {
  description = "Amazon Resource Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.asg.arn
}

output "target_group_arn" {
  description = "Target Group ARN; consumed by verify-rehydration.sh for ELB health queries"
  value       = aws_lb_target_group.app.arn
}

output "launch_template_id" {
  description = "Identifier of the launch template tracking the current Golden AMI"
  value       = aws_launch_template.rehydration_target.id
}

output "latest_launch_template_version" {
  description = "Latest launch template revision deployed during the active rehydration run"
  value       = aws_launch_template.rehydration_target.latest_version
}
