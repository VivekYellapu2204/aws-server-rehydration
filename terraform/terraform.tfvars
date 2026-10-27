environment               = "production"
vpc_id                    = "vpc-0123456789abcdef0"
subnet_ids                = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
security_group_ids        = ["sg-0123456789abcdef0"]
target_ami_id             = "ami-0123456789abcdef0"
instance_type             = "t3.medium"
iam_instance_profile_name = "app-workload-instance-profile"

target_drain_timeout_sec     = 300
healthcheck_grace_period_sec = 300
min_healthy_percentage       = 90
instance_warmup_sec          = 300

asg_min_size         = 2
asg_max_size         = 8
asg_desired_capacity = 4
