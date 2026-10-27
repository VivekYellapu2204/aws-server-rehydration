variable "environment" {
  type        = string
  description = "Target deployment tier identifier (e.g., staging, prod)"
  default     = "prod"
}

variable "vpc_id" {
  type        = string
  description = "Virtual Private Cloud ID hosting the application fleet"
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of private subnet IDs across multiple AZs for ASG placement"
}

variable "security_group_ids" {
  type        = list(string)
  description = "Security groups attached to the rehydrated compute instances"
}

variable "target_ami_id" {
  type        = string
  description = "Pre-baked, CIS-hardened Golden AMI ID used for the rehydration rollout"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance sizing"
  default     = "t3.medium"
}

variable "iam_instance_profile_name" {
  type        = string
  description = "IAM instance profile assigned to instances for SSM and CloudWatch monitoring"
}

variable "target_drain_timeout_sec" {
  type        = number
  description = "Connection draining timeout in seconds for ALB target deregistration"
  default     = 300
}

variable "healthcheck_grace_period_sec" {
  type        = number
  description = "Grace period buffer before the ASG evaluates ELB health status"
  default     = 300
}

variable "min_healthy_percentage" {
  type        = number
  description = "Percentage of fleet capacity that must remain healthy throughout instance refresh"
  default     = 90
}

variable "instance_warmup_sec" {
  type        = number
  description = "Warm-up window in seconds before newly initialized instances serve traffic"
  default     = 300
}

variable "asg_min_size" {
  type        = number
  description = "Minimum instance threshold for the Auto Scaling Group"
  default     = 2
}

variable "asg_max_size" {
  type        = number
  description = "Maximum instance capacity limit for the Auto Scaling Group"
  default     = 10
}

variable "asg_desired_capacity" {
  type        = number
  description = "Baseline operational instance count"
  default     = 4
}
