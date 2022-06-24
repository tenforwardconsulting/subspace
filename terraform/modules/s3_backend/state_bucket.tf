# S3 Bucket for storing state
resource "aws_s3_bucket" "state_bucket" {
  bucket = local.state_bucket_name
  acl    = "private"

  versioning {
    enabled = true
  }

  tags = {
    Name        = "Subspace Terraform State"
    Environment = "Global"
  }
}