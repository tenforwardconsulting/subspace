# Global (e.g. include -var-file=../global.vars)

variable aws_region { type = string }
variable aws_access_key_id {}
variable aws_secret_access_key {}
variable project_name { type = string }
variable project_environment { type = string }
variable domain_name { type = string}


# single_ec2.tf
variable instance_type { type = string }
variable instance_ami  { type = string }
variable instance_user { type = string }
variable ssh_cidr_blocks {
  default = ["0.0.0.0/0"]
}

locals {
  instance_hostname = "${var.project_environment}-main"
}