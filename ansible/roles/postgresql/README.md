Attach this as a bucket policy to allow unauthenticated writes. Then you can set "s3_db_backup_bucket" to upload backups to your s3 bucket instead of keeping backups on the local machine.
#TODO: add authentication option
{
    "Version": "2012-10-17",
    "Id": "Policy1477442935689",
    "Statement": [
        {
            "Sid": "Stmt1477442933718",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::<BUCKET_NAME>/*"
        }
    ]
}
