variable "source_bucket_id" {
  description = "ID of the source bucket"
  type        = string
}

variable "source_bucket_arn" {
  description = "ARN of the source bucket"
  type        = string
}

variable "source_kms_key_arn" {
  description = "Optional source KMS key ARN when source bucket uses KMS"
  type        = string
  default     = ""
}

variable "source_additional_kms_key_arns" {
  description = "Optional additional source KMS key ARNs for replicating SSE-KMS objects encrypted with keys other than source_kms_key_arn"
  type        = list(string)
  default     = []
}

variable "iam_user_policy_name" {
  description = "Base policy name used for replication IAM resources"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "name" {
  description = "Bucket name"
  type        = string
}

variable "tags" {
  description = "Tags to apply to replication IAM resources"
  type        = map(any)
  default     = {}
}

variable "replication_destination_bucket_arn" {
  description = "ARN of the destination S3 bucket for replication"
  type        = string
}

variable "replication_destination_account_id" {
  description = "Destination AWS account ID for cross-account replication ownership takeover"
  type        = string
  default     = ""
}

variable "replication_destination_storage_class" {
  description = "Optional storage class override for replicated objects. When omitted, source object storage class is preserved where supported"
  type        = string
  default     = null
  nullable    = true
}

variable "replication_destination_kms_key_arn" {
  description = "Optional destination KMS key ARN for encrypting replicated objects"
  type        = string
  default     = ""
}

variable "replication_report_bucket_arn" {
  description = "Optional S3 bucket ARN for S3 Batch Replication completion reports. Defaults to replication_destination_bucket_arn"
  type        = string
  default     = ""
}

variable "replication_prefix" {
  description = "Object prefix to replicate. Leave empty to replicate all objects"
  type        = string
  default     = ""
}

variable "replication_delete_marker_replication_status" {
  description = "Delete marker replication status. Valid values are Enabled or Disabled"
  type        = string
  default     = "Enabled"
}

variable "replication_metrics_enabled" {
  description = "Enable S3 replication metrics and event notifications"
  type        = bool
  default     = false
}

variable "replication_time_control_enabled" {
  description = "Enable S3 Replication Time Control. Requires replication metrics"
  type        = bool
  default     = false

  validation {
    condition     = !var.replication_time_control_enabled || var.replication_metrics_enabled
    error_message = "replication_time_control_enabled requires replication_metrics_enabled to also be true."
  }
}

variable "replication_replica_modifications_enabled" {
  description = "Enable replica modification sync for advanced bidirectional-style replication scenarios"
  type        = bool
  default     = false
}

