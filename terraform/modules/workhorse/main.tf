terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

# Subspace will prompt for credentials if they are not found in ~/.aws/credentials
provider aws {
  region = var.aws_region
  profile = "subspace-${var.project_name}"
}

resource "aws_key_pair" "subspace" {
  key_name   = "subspace"
  public_key = file("../../subspace.pem.pub")
}