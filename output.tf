output "s3_bucket_id" {
  description = "ID of generated S3 bucket"
  value       = element(concat(aws_s3_bucket.this.*.id, [""]), 0)
}

output "s3_bucket_arn" {
  description = "ARN of generated S3 bucket"
  value       = element(concat(aws_s3_bucket.this.*.arn, [""]), 0)
}

output "s3_bucket_kms_key" {
  description = "KMS Key ID of the generated bucket"
  value       = element(concat(aws_kms_key.this.*.key_id, [""]), 0)
}

output "s3_bucket_kms_key_arn" {
  description = "KMS Key ARN of the generated bucket"
  value       = element(concat(aws_kms_key.this.*.arn, [""]), 0)
}
output "replication_role_arn" {
  description = "ARN of the IAM role used by S3 replication (empty when replication is disabled)"
  value       = element(concat(module.replication.*.replication_role_arn, [""]), 0)
}
