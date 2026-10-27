terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Application Load Balancer Target Group with strict draining
resource "aws_lb_target_group" "app" {
  name                 = "${var.environment}-app-tg"
  port                 = 8080
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "instance"
  deregistration_delay = var.target_drain_timeout_sec

  health_check {
    enabled             = true
    path                = "/healthz"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 15
    matcher             = "200"
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Immutable Launch Template pointing to pre-baked Golden AMI
resource "aws_launch_template" "rehydration_target" {
  name_prefix   = "${var.environment}-rehydration-template-"
  image_id      = var.target_ami_id
  instance_type = var.instance_type

  vpc_security_group_ids = var.security_group_ids

  iam_instance_profile {
    name = var.iam_instance_profile_name
  }

  monitoring {
    enabled = true
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              systemctl start app.service
              EOF
  )

  lifecycle {
    create_before_destroy = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Environment = var.environment
      Role        = "ApplicationServer"
    }
  }
}

# Auto Scaling Group with Native Instance Refresh & Circuit Breaker
resource "aws_autoscaling_group" "asg" {
  name_prefix         = "${var.environment}-asg-"
  vpc_zone_identifier = var.subnet_ids
  target_group_arns   = [aws_lb_target_group.app.arn]

  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = var.asg_desired_capacity

  health_check_type         = "ELB"
  health_check_grace_period = var.healthcheck_grace_period_sec
  force_delete              = false

  launch_template {
    id      = aws_launch_template.rehydration_target.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = var.min_healthy_percentage
      instance_warmup        = var.instance_warmup_sec
      auto_rollback          = true
    }
    triggers = ["tag"]
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }
}
