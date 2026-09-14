output "replication_role_arn" {
  description = "ARN of the IAM role assumed by S3 to replicate objects to the destination bucket"
  value       = aws_iam_role.s3_replication.arn
}
