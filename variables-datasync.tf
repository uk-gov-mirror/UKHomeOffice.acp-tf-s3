variable "datasync_source_access_enabled" {
  description = "Enable DataSync source access policy and source KMS decrypt grants"
  type        = bool
  default     = false
}

variable "datasync_source_role_arns" {
  description = "Optional IAM role ARNs used by DataSync to read from this source bucket. When set, the module grants source bucket read and source KMS decrypt access"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.datasync_source_role_arns : can(regex("^arn:aws:iam::[0-9]{12}:role/.+", arn))])
    error_message = "Each datasync_source_role_arns entry must be a valid IAM role ARN (arn:aws:iam::<account-id>:role/<role-name>)."
  }

  validation {
    condition     = !var.datasync_source_access_enabled || length(var.datasync_source_role_arns) > 0
    error_message = "datasync_source_role_arns must be provided when datasync_source_access_enabled is true."
  }
}
