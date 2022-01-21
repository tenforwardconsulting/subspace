terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider aws {
  region = var.aws_region
  # Set these values locally in credentials.auto.tfvars
  access_key = var.aws_access_key_id
  secret_key = var.aws_secret_access_key
}

resource "aws_key_pair" "subspace" {
  key_name   = "subspace"
  public_key = file("../../subspace.pem.pub")
}