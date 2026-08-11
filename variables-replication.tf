variable "replication_enabled" {
  description = "Enable cross-bucket replication from this bucket to a destination bucket"
  type        = bool
  default     = false
}

variable "replication_destination_bucket_arn" {
  description = "ARN of the destination S3 bucket for replication"
  type        = string
  default     = ""

  validation {
    condition     = !var.replication_enabled || var.replication_destination_bucket_arn != ""
    error_message = "replication_destination_bucket_arn must be provided when replication_enabled is true."
  }
}

variable "replication_destination_account_id" {
  description = "Destination AWS account ID for cross-account replication ownership takeover. Leave empty for same-account replication"
  type        = string
  default     = ""

  validation {
    condition     = var.replication_destination_account_id == "" || can(regex("^[0-9]{12}$", var.replication_destination_account_id))
    error_message = "replication_destination_account_id must be empty or a 12-digit AWS account ID."
  }
}

variable "replication_destination_storage_class" {
  description = "Optional storage class override for replicated objects. When omitted, source object storage class is preserved where supported"
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = var.replication_destination_storage_class == null || var.replication_destination_storage_class == "" || contains([
      "STANDARD",
      "REDUCED_REDUNDANCY",
      "STANDARD_IA",
      "ONEZONE_IA",
      "INTELLIGENT_TIERING",
      "GLACIER",
      "DEEP_ARCHIVE",
      "GLACIER_IR",
    ], var.replication_destination_storage_class)
    error_message = "replication_destination_storage_class must be null/empty or a valid S3 storage class override."
  }
}

variable "replication_destination_kms_key_arn" {
  description = "Destination KMS key ARN for replicated objects. Required when replication is enabled so replicas are always written with a defined KMS key"
  type        = string
  default     = ""

  validation {
    condition     = !var.replication_enabled || var.replication_destination_kms_key_arn != ""
    error_message = "replication_destination_kms_key_arn must be provided when replication_enabled is true."
  }
}

variable "replication_report_bucket_arn" {
  description = "Optional S3 bucket ARN for S3 Batch Replication completion reports. Defaults to replication_destination_bucket_arn"
  type        = string
  default     = ""

  validation {
    condition     = var.replication_report_bucket_arn == "" || can(regex("^arn:aws:s3:::[A-Za-z0-9.-]{3,63}$", var.replication_report_bucket_arn))
    error_message = "replication_report_bucket_arn must be empty or a valid S3 bucket ARN (arn:aws:s3:::bucket-name)."
  }
}

variable "replication_report_bucket_kms_key_arn" {
  description = "Optional KMS key ARN for encrypting S3 Batch Replication reports written to replication_report_bucket_arn. Defaults to replication_destination_kms_key_arn"
  type        = string
  default     = ""
}

variable "replication_source_kms_key_arns" {
  description = "Optional additional source KMS key ARNs for replicating SSE-KMS objects when the source bucket contains objects encrypted with keys other than the module-managed bucket key"
  type        = list(string)
  default     = []
}

variable "replication_prefix" {
  description = "Object prefix to replicate. Leave empty to replicate all objects"
  type        = string
  default     = ""
}

variable "replication_delete_marker_replication_status" {
  description = "Delete marker replication status. Defaults to Enabled so deletes mirror by default. Valid values are Enabled or Disabled"
  type        = string
  default     = "Enabled"

  validation {
    condition     = contains(["Enabled", "Disabled"], var.replication_delete_marker_replication_status)
    error_message = "replication_delete_marker_replication_status must be either Enabled or Disabled."
  }
}

variable "replication_metrics_enabled" {
  description = "Enable S3 replication metrics and event notifications"
  type        = bool
  default     = false
}

variable "replication_time_control_enabled" {
  description = "Enable S3 Replication Time Control. Requires replication_metrics_enabled"
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
