# Global (e.g. include -var-file=../global.vars)

variable aws_region { type = string }
variable project_name { type = string }
variable project_environment { type = string }



# single_ec2.tf
variable instance_type { type = string }
variable instance_ami  { type = string }