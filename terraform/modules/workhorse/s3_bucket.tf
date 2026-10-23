resource "aws_s3_bucket" "bucket" {
  bucket = "${var.project_name}-${var.project_environment}-bucket"
}

resource "aws_s3_bucket_public_access_block" "block_public_acls" {
  bucket = aws_s3_bucket.bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_user" "s3_user" {
  name = "${var.project_name}-${var.project_environment}_s3"
}

resource "aws_iam_user_policy" "s3-bucket-up" {
  name = "${var.project_name}"
  user = aws_iam_user.s3_user.name

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
            "s3:PutObject",
            "s3:PutObjectAcl",
            "s3:GetObject",
            "s3:GetObjectVersion",
            "s3:GetBucketAcl",
            "s3:DeleteObject",
            "s3:DeleteObjectVersion"
            ],
            "Effect": "Allow",
            "Resource": [
                "arn:aws:s3:::${var.project_name}-${var.project_environment}",
                "arn:aws:s3:::${var.project_name}-${var.project_environment}/*"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_access_key" "s3_user" {
  user = aws_iam_user.s3_user.name
}

output "AWS_ACCESS_KEY_ID" {
  value = aws_iam_access_key.s3_user.id
}

output "AWS_SECRET_ACCESS_KEY" {
  value = aws_iam_access_key.s3_user.secret
  sensitive = true
}

