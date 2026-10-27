packer {
  required_version = ">= 1.9.0"
  required_plugins {
    amazon = {
      version = ">= 1.2.8"
      source  = "github.com/hashicorp/amazon"
    }
    ansible = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region for AMI baking"
  default     = "us-east-1"
}

variable "environment" {
  type        = string
  description = "Environment identifier tag"
  default     = "production"
}

variable "vpc_id" {
  type        = string
  description = "Target VPC ID where the temporary build instance will run"
  default     = env("BUILD_VPC_ID")
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID where the temporary build instance will run"
  default     = env("BUILD_SUBNET_ID")
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type used during image baking"
  default     = "t3.medium"
}

# Lookup latest official baseline Amazon Linux 2023 AMI
data "amazon-ami" "base_linux" {
  filters = {
    name                = "al2023-ami-2023.*-x86_64"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["amazon"]
  region      = var.aws_region
}

source "amazon-ebs" "rehydration_ami" {
  region                      = var.aws_region
  source_ami                  = data.amazon-ami.base_linux.id
  instance_type               = var.instance_type
  ssh_username                = "ec2-user"
  associate_public_ip_address = false
  vpc_id                      = var.vpc_id
  subnet_id                   = var.subnet_id

  ami_name        = "${var.environment}-golden-ami-{{timestamp}}"
  ami_description = "Immutable Golden AMI baked for zero-downtime server rehydration"

  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = 30
    volume_type           = "gp3"
    iops                  = 3000
    throughput            = 125
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name          = "${var.environment}-golden-ami-{{timestamp}}"
    Environment   = var.environment
    BaseAmiId     = "{{ .SourceAMI }}"
    BakedBy       = "Packer"
    PipelineType  = "ServerRehydration"
  }
}

build {
  name    = "bake-hardened-ami"
  sources = ["source.amazon-ebs.rehydration_ami"]

  # Wait for cloud-init to finish before running provisioning
  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init...'",
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do sleep 2; done"
    ]
  }

  # Execute configuration and hardening playbook
  provisioner "ansible" {
    playbook_file = "${path.root}/../ansible/playbook.yml"
    user          = "ec2-user"
    use_proxy     = false
    extra_arguments = [
      "--extra-vars", "target_env=${var.environment}"
    ]
  }

  # Export manifest containing new AMI ID for downstream CI/CD consumption
  post-processor "manifest" {
    output     = "packer-manifest.json"
    strip_path = true
  }
}
