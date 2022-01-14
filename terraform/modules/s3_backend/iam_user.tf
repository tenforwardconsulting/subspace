resource "aws_iam_user" "ss" {
  name = "subspace"
  path = "/"

  tags = {
    Name = "Subspace IAM user"
    Environment = "Global"
  }
}

resource "aws_iam_access_key" "ss" {
  user = aws_iam_user.ss.name

  pgp_key = data.local_file.pgp_key.content_base64
}

resource "aws_iam_user_policy" "ss_s3" {
  name = "ss_s3_user_policy"
  user = aws_iam_user.ss.name

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::${local.state_bucket_name}"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject"],
      "Resource": "arn:aws:s3:::${local.state_bucket_name}/*"
    }
  ]
}
EOF
}