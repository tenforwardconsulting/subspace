terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

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
  key_name   = "subspace-${var.project_name}-${var.project_environment}"
  public_key = var.subspace_public_key
}

resource "aws_kms_key" "subspace" {
  description             = "Subspace managed KMS key"
  deletion_window_in_days = 10
}

