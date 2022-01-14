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
  # Bring your own credentials for now via
  # AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
}

resource "aws_key_pair" "subspace" {
  key_name   = "subspace"
  public_key = file("../../subspace.pem.pub")
}