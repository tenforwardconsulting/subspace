terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

# Variables
variable aws_region {
  type = string
}

variable project_name {
  type = string
}

locals {
  state_bucket_name = "subspace-backend-${var.project_name}"
}

provider "aws" {
  region = var.aws_region
}

data "local_file" "pgp_key" {
  filename = "../public-key-binary.gpg"
}

# Outputs

output "subspace_aws_access_key_id" {
  value = aws_iam_access_key.ss.id
}

output "subspace_aws_encrypted_secret_access_key" {
  value = aws_iam_access_key.ss.encrypted_secret
}