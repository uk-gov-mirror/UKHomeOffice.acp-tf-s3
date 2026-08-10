data "aws_iam_policy_document" "s3_replication_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com", "batchoperations.s3.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_caller_identity" "current" {}

locals {
  replication_role_suffix       = "-s3-replication-role"
  replication_role_prefix_max   = 64 - length(local.replication_role_suffix)
  default_replication_role_name = "${substr(var.name, 0, local.replication_role_prefix_max)}${local.replication_role_suffix}"
  default_replication_rule_id   = "${var.name}-replication-rule"
  destination_account_id        = var.replication_destination_account_id != "" ? var.replication_destination_account_id : data.aws_caller_identity.current.account_id
  ownership_override_enabled    = local.destination_account_id != data.aws_caller_identity.current.account_id
  report_bucket_arn             = var.replication_report_bucket_arn != "" ? var.replication_report_bucket_arn : var.replication_destination_bucket_arn
  report_bucket_kms_key_arn     = var.replication_report_bucket_kms_key_arn != "" ? var.replication_report_bucket_kms_key_arn : var.replication_destination_kms_key_arn
  source_kms_key_arns           = distinct(compact(concat(var.source_kms_key_arn != "" ? [var.source_kms_key_arn] : [], var.source_additional_kms_key_arns)))
}

resource "aws_iam_role" "s3_replication" {
  name               = local.default_replication_role_name
  assume_role_policy = data.aws_iam_policy_document.s3_replication_assume_role.json

  tags = merge(
    var.tags,
    {
      "Name" = format("%s-%s-replication", var.environment, var.name)
    },
    {
      "Env" = var.environment
    },
  )
}

resource "aws_iam_policy" "s3_replication" {
  name = "${var.iam_user_policy_name}-S3ReplicationPolicy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect = "Allow"
          Action = [
            "s3:GetReplicationConfiguration",
            "s3:ListBucket",
            "s3:PutInventoryConfiguration",
          ]
          Resource = [var.source_bucket_arn]
        },
        {
          Effect = "Allow"
          Action = [
            "s3:InitiateReplication",
            "s3:GetObjectVersionForReplication",
            "s3:GetObjectVersionAcl",
            "s3:GetObjectVersionTagging",
            "s3:GetObjectRetention",
            "s3:GetObjectLegalHold",
          ]
          Resource = ["${var.source_bucket_arn}/*"]
        },
        {
          Effect = "Allow"
          Action = [
            "s3:ReplicateObject",
            "s3:ReplicateDelete",
            "s3:ReplicateTags",
            "s3:ObjectOwnerOverrideToBucketOwner",
          ]
          Resource = ["${var.replication_destination_bucket_arn}/*"]
        },
        {
          Effect = "Allow"
          Action = [
            "s3:GetBucketLocation",
            "s3:ListBucket",
            "s3:GetObject",
            "s3:GetObjectVersion",
            "s3:PutObject",
            "s3:PutObjectAcl",
          ]
          Resource = [
            local.report_bucket_arn,
            "${local.report_bucket_arn}/*",
          ]
        },
      ],
      length(local.source_kms_key_arns) > 0 ? [
        {
          Effect = "Allow"
          Action = [
            "kms:Decrypt",
            "kms:DescribeKey",
          ]
          Resource = local.source_kms_key_arns
        },
      ] : [],
      [
        {
          Effect = "Allow"
          Action = [
            "kms:Decrypt",
            "kms:Encrypt",
            "kms:ReEncrypt*",
            "kms:GenerateDataKey*",
            "kms:DescribeKey",
          ]
          Resource = distinct(compact([
            var.replication_destination_kms_key_arn,
            local.report_bucket_kms_key_arn,
          ]))
        },
      ],
    )
  })

  description = "Policy used by S3 to replicate objects to destination bucket"
}

resource "aws_iam_role_policy_attachment" "s3_replication" {
  role       = aws_iam_role.s3_replication.name
  policy_arn = aws_iam_policy.s3_replication.arn
}

resource "aws_s3_bucket_replication_configuration" "this" {
  bucket = var.source_bucket_id
  role   = aws_iam_role.s3_replication.arn

  rule {
    id     = local.default_replication_rule_id
    status = "Enabled"

    delete_marker_replication {
      status = var.replication_delete_marker_replication_status
    }

    filter {
      prefix = var.replication_prefix
    }

    destination {
      bucket        = var.replication_destination_bucket_arn
      account       = local.ownership_override_enabled ? local.destination_account_id : null
      storage_class = var.replication_destination_storage_class == null || var.replication_destination_storage_class == "" ? null : var.replication_destination_storage_class

      dynamic "access_control_translation" {
        for_each = local.ownership_override_enabled ? [1] : []
        content {
          owner = "Destination"
        }
      }

      encryption_configuration {
        replica_kms_key_id = var.replication_destination_kms_key_arn
      }

      dynamic "metrics" {
        for_each = var.replication_metrics_enabled ? [1] : []
        content {
          status = "Enabled"

          event_threshold {
            minutes = 15
          }
        }
      }

      dynamic "replication_time" {
        for_each = var.replication_time_control_enabled ? [1] : []
        content {
          status = "Enabled"

          time {
            minutes = 15
          }
        }
      }
    }

    # Required when a replica KMS key is configured, and also enables replication of
    # SSE-KMS source objects while SSE-S3 objects continue to replicate normally.
    source_selection_criteria {
      dynamic "replica_modifications" {
        for_each = var.replication_replica_modifications_enabled ? [1] : []
        content {
          status = "Enabled"
        }
      }

      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }
  }

  depends_on = [aws_iam_role_policy_attachment.s3_replication]
}
