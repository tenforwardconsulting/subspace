terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Subspace will prompt for credentials if they are not found in ~/.aws/credentials
provider aws {
  region = var.aws_region
  default_tags {
    tags = {
      Environment = var.project_environment
      Project     = var.project_name
    }
  }
}

resource "aws_key_pair" "subspace" {
  key_name   = "${var.project_name} ${var.project_environment} subspace"
  public_key = var.subspace_public_key
}
