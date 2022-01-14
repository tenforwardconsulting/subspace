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
}

resource "aws_key_pair" "subspace" {
  key_name   = "subspace"
  public_key = file("../../../subspace.pem.pub")
}

