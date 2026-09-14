# acp-tf-s3 S3 bucket terraform module

Module usage:

     module "s3" {

        source = "git::https://github.com/UKHomeOffice/acp-tf-s3?ref=master"

        name                 = "fake"
        acl                  = "private"
        environment          = "${var.environment}"
        kms_alias            = "mykey"
        bucket_iam_user      = "fake-s3-bucket-user"
        iam_user_policy_name = "fake-s3-bucket-policy"

     }

The bucket created is always encrypted.

If the `website_hosting` parameter is set to `true`, default AES256 encryption is used.

For standard buckets, KMS encryption is used if a `kms_alias` is provided. If `kms_alias` is not provided, default AES256 encryption is used.

| encryption type       | `website_hosting` is `true` |`website_hosting` is `false` |
|-----------------------|-----------------------------|-----------------------------|
| `kms_alias` specified | AES256                      | KMS                         |
| `kms_alias` is `""`   | AES256                      | AES256                      |

## Replication support

This module now supports optional S3 replication so data can be continuously synced to a destination bucket ahead of platform cutover.

Enable replication by setting:

- `replication_enabled = true`
- `replication_destination_bucket_arn` to the target bucket ARN
- `replication_destination_kms_key_arn` to encrypt replicas with a defined destination KMS key

Optional replication settings:

- `replication_destination_account_id` to identify the destination account for cross-account ownership takeover; omit it for same-account replication
- `replication_destination_storage_class` to force replicas into a specific class (optional; if omitted, source storage class is preserved where supported)
- `replication_source_kms_key_arns` to allow replication of source SSE-KMS objects encrypted with additional source keys
- `replication_report_bucket_arn` when S3 Batch Replication completion reports should be written to a bucket other than `replication_destination_bucket_arn`
- `datasync_source_access_enabled = true` to opt into DataSync source-access policy path
- `datasync_source_role_arns` to grant DataSync source-read access (bucket policy grants and source KMS decrypt key-policy access are managed by the root module)
- `replication_prefix` to replicate only a subset of objects
- `replication_metrics_enabled` to emit replication metrics and notifications
- `replication_time_control_enabled` to opt into S3 Replication Time Control (requires `replication_metrics_enabled = true`)

Replication IAM role naming is deterministic and internal: `<bucket_name>-s3-replication-role`, truncated to IAM's 64-character limit.

Replication behavior:

- Replicas are always written using the configured `replication_destination_kms_key_arn`
- Cross-account replication switches replica ownership to the destination account when `replication_destination_account_id` is set to a different account ID
- Source buckets can contain a mix of SSE-S3 and SSE-KMS objects
- If source SSE-KMS objects use keys other than the module-managed bucket key, supply those extra key ARNs in `replication_source_kms_key_arns`
- S3 Batch Replication completion report permissions are scoped to `replication_report_bucket_arn` when set, otherwise `replication_destination_bucket_arn`
- DataSync source bucket policy grants are composed into the root bucket policy document for TLS, website, and standard modes so policy ownership remains single-source
- DataSync source access remains disabled unless `datasync_source_access_enabled = true`
- Delete markers replicate by default so the destination bucket stays in sync with source deletes
- Replication Time Control stays disabled unless you explicitly opt in

When replication is enabled, source bucket versioning is automatically set to `Enabled` because S3 replication requires versioning.

Example:

```hcl
module "s3" {
   source = "git::https://github.com/UKHomeOffice/acp-tf-s3?ref=master"

   name                 = "legacy-prod-data"
   environment          = var.environment
   bucket_iam_user      = "legacy-prod-data-user"
   iam_user_policy_name = "legacy-prod-data-policy"

   replication_enabled                 = true
   replication_destination_bucket_arn  = "arn:aws:s3:::new-platform-prod-data"
   replication_destination_account_id  = "123456789012"
   replication_destination_kms_key_arn = "arn:aws:kms:eu-west-2:123456789012:key/abcd-1234"
}
```

To opt into S3 Replication Time Control:

```hcl
module "s3" {
   source = "git::https://github.com/UKHomeOffice/acp-tf-s3?ref=master"

   name                                = "legacy-prod-data"
   environment                         = var.environment
   bucket_iam_user                     = "legacy-prod-data-user"
   iam_user_policy_name                = "legacy-prod-data-policy"
   replication_enabled                  = true
   replication_destination_bucket_arn   = "arn:aws:s3:::new-platform-prod-data"
   replication_destination_account_id   = "123456789012"
   replication_destination_kms_key_arn  = "arn:aws:kms:eu-west-2:123456789012:key/abcd-1234"
   replication_metrics_enabled          = true
   replication_time_control_enabled     = true
}
```

## Upgrading

v2 of the module is not backwards-compatible with v1 following refactoring of the module.

Because of the limitations of terraform at the time, there were 4 versions of an `aws_s3_bucket` that were conditionally created, with only one out of the 4 options actually creating a bucket.

This caused issues when a tenant initially requested a bucket without logging and later on asked for logging to be turned on: this meant that the module wanted to destroy one bucket resource and create another one. This meant that the pipeline would fail (due to buckets not being empty) until the terraform state was also refactored.

In v2 of the module, there is a single `aws_s3_bucket` resource and the 4 options have the appropriate blocks created dynamically (standard bucket, website bucket) x (no logging, logging enabled).

If the state refactoring is performed in a `terraform-toolset` container, replace `terraform` below with `/acp/bin/run.sh`

### Upgrading a standard bucket with no logging enabled

Replace `standard_bucket` below with the name of the module creating the bucket.

```
terraform state mv module.standard_bucket.aws_kms_alias.s3_bucket_kms_alias[0] module.standard_bucket.aws_kms_alias.this[0]
terraform state mv module.standard_bucket.aws_kms_key.s3_bucket_kms_key[0] module.standard_bucket.aws_kms_key.this[0]
terraform state mv module.standard_bucket.aws_s3_bucket.s3_bucket[0] module.standard_bucket.aws_s3_bucket.this
```

### Upgrading a standard bucket with audit logs enabled

Replace `audit_bucket` below with the name of the module creating the audit bucket and `bucket_with_logging` with the name of the tenant bucket that has logging enabled.

``` bash
# refactoring for the audit bucket
terraform state mv module.audit_bucket.aws_kms_alias.s3_bucket_kms_alias[0] module.audit_bucket.aws_kms_alias.this[0]
terraform state mv module.audit_bucket.aws_kms_key.s3_bucket_kms_key[0] module.audit_bucket.aws_kms_key.this[0]
terraform state mv module.audit_bucket.aws_s3_bucket.s3_bucket[0] module.audit_bucket.aws_s3_bucket.this
#
# refactoring for the bucket with logging enabled
terraform state mv module.bucket_with_logging.aws_kms_alias.s3_bucket_kms_alias[0] module.bucket_with_logging.aws_kms_alias.this[0]
terraform state mv module.bucket_with_logging.aws_kms_key.s3_bucket_kms_key[0] module.bucket_with_logging.aws_kms_key.this[0]
terraform state mv module.bucket_with_logging.aws_s3_bucket.s3_bucket_with_logging[0] module.bucket_with_logging.aws_s3_bucket.this
```

### Upgrading a website bucket with no logging enabled

Replace `website_bucket` below with the name of the module creating the bucket.

```
terraform state mv module.website_bucket.aws_s3_bucket.s3_website_bucket[0] module.website_bucket.aws_s3_bucket.this
```

### Upgrading a website bucket with audit logs enabled

Replace `audit_bucket` below with the name of the module creating the audit bucket and `website_bucket_with_logging` with the name of the tenant website bucket that has logging enabled.


``` bash
# refactoring for the audit bucket
terraform state mv module.audit_bucket.aws_s3_bucket.s3_bucket[0] module.audit_bucket.aws_s3_bucket.this
#
# refactoring for the bucket with logging enabled
terraform state mv module.website_bucket_with_logging.aws_s3_bucket.s3_website_bucket_with_logging[0] module.website_bucket_with_logging.aws_s3_bucket.this
```

### Upgrade notes

Please note the following:

- the KMS key will be amended to enable automatic key rotation. Any already encrypted will still be able to be decrypted with any previous keys replaced by the AWS automatic key rotation process.
- if you set the `block_public_access` module property to `true`, a new resource will be created and a number of bucket policy resources will be modified to make sure that public access is not granted.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 3.0, < 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 4.67.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_replication"></a> [replication](#module\_replication) | ./modules/replication | n/a |
| <a name="module_self_serve_access_keys"></a> [self\_serve\_access\_keys](#module\_self\_serve\_access\_keys) | git::https://github.com/UKHomeOffice/acp-tf-self-serve-access-keys | v0.2.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_policy.s3_bucket_iam_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.s3_bucket_iam_website_policy_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.s3_bucket_iam_whitelist_ip_and_vpc_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.s3_bucket_iam_whitelist_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.s3_bucket_with_kms_and_whitelist_iam_policy_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.s3_bucket_with_kms_and_whitelist_iam_policy_2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.s3_bucket_with_kms_and_whitelist_ip_and_vpc_iam_policy_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.s3_bucket_with_kms_and_whitelist_ip_and_vpc_iam_policy_2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.s3_bucket_with_kms_and_whitelist_vpc_iam_policy_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.s3_bucket_with_kms_and_whitelist_vpc_iam_policy_2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.s3_bucket_with_kms_iam_policy_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.s3_bucket_with_kms_iam_policy_2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.s3_bucket_with_whitelist_vpc_iam_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.s3_tls_bucket_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_user.s3_bucket_iam_user](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user) | resource |
| [aws_iam_user_policy_attachment.attach_s3_bucket_iam_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user_policy_attachment) | resource |
| [aws_iam_user_policy_attachment.attach_s3_bucket_whitelist_iam_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user_policy_attachment) | resource |
| [aws_iam_user_policy_attachment.attach_s3_bucket_whitelist_ip_and_vpc_iam_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user_policy_attachment) | resource |
| [aws_iam_user_policy_attachment.attach_s3_bucket_with_kms_and_whitelist_iam_policy_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user_policy_attachment) | resource |
| [aws_iam_user_policy_attachment.attach_s3_bucket_with_kms_and_whitelist_iam_policy_2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user_policy_attachment) | resource |
| [aws_iam_user_policy_attachment.attach_s3_bucket_with_kms_and_whitelist_ip_and_vpc_iam_policy_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user_policy_attachment) | resource |
| [aws_iam_user_policy_attachment.attach_s3_bucket_with_kms_and_whitelist_ip_and_vpc_iam_policy_2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user_policy_attachment) | resource |
| [aws_iam_user_policy_attachment.attach_s3_bucket_with_kms_and_whitelist_vpc_iam_policy_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user_policy_attachment) | resource |
| [aws_iam_user_policy_attachment.attach_s3_bucket_with_kms_and_whitelist_vpc_iam_policy_2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user_policy_attachment) | resource |
| [aws_iam_user_policy_attachment.attach_s3_bucket_with_kms_iam_policy_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user_policy_attachment) | resource |
| [aws_iam_user_policy_attachment.attach_s3_bucket_with_kms_iam_policy_2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user_policy_attachment) | resource |
| [aws_iam_user_policy_attachment.attach_s3_bucket_with_whitelist_vpc_iam_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user_policy_attachment) | resource |
| [aws_iam_user_policy_attachment.attach_s3_tls_bucket_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user_policy_attachment) | resource |
| [aws_iam_user_policy_attachment.attach_s3_website_bucket_iam_policy_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user_policy_attachment) | resource |
| [aws_kms_alias.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_s3_bucket.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_accelerate_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_accelerate_configuration) | resource |
| [aws_s3_bucket_acl.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_acl) | resource |
| [aws_s3_bucket_cors_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_cors_configuration) | resource |
| [aws_s3_bucket_lifecycle_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_logging.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_logging) | resource |
| [aws_s3_bucket_ownership_controls.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.datasync_source_bucket_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_policy.enforce_tls_bucket_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_policy.s3_website_bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.s3_bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.aes](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.kms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_s3_bucket_website_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_website_configuration) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.kms_key_policy_document](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.kms_key_policy_document_whitelist](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.kms_key_with_whitelist_ip_and_vpc_policy_document](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.kms_key_with_whitelist_vpc_policy_document](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.s3_bucket_policy_document](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.s3_bucket_policy_document_whitelist](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.s3_bucket_with_kms_and_whitelist_ip_and_vpc_policy_document_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.s3_bucket_with_kms_and_whitelist_ip_and_vpc_policy_document_2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.s3_bucket_with_kms_and_whitelist_vpc_policy_document_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.s3_bucket_with_kms_and_whitelist_vpc_policy_document_2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.s3_bucket_with_kms_policy_document_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.s3_bucket_with_kms_policy_document_2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.s3_bucket_with_kms_policy_document_whitelist_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.s3_bucket_with_kms_policy_document_whitelist_2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.s3_bucket_with_kms_website_policy_document_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.s3_bucket_with_whitelist_ip_and_vpc_policy_document](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.s3_bucket_with_whitelist_vpc_policy_document](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.s3_tls_bucket_policy_document](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_acceleration_status"></a> [acceleration\_status](#input\_acceleration\_status) | Sets the accelerate configuration of an existing bucket. Can be Enabled or Suspended. | `string` | `"Suspended"` | no |
| <a name="input_acl"></a> [acl](#input\_acl) | The access control list assigned to this bucket | `string` | `"private"` | no |
| <a name="input_block_public_access"></a> [block\_public\_access](#input\_block\_public\_access) | Blocks all public access to the bucket | `bool` | `false` | no |
| <a name="input_bucket_iam_user"></a> [bucket\_iam\_user](#input\_bucket\_iam\_user) | The name of the iam user assigned to the created s3 bucket | `string` | n/a | yes |
| <a name="input_cmk_enable_key_rotation"></a> [cmk\_enable\_key\_rotation](#input\_cmk\_enable\_key\_rotation) | Enables CMK key rotation | `bool` | `true` | no |
| <a name="input_cors_allowed_headers"></a> [cors\_allowed\_headers](#input\_cors\_allowed\_headers) | Specifies which headers are allowed. | `list` | <pre>[<br/>  "Authorization"<br/>]</pre> | no |
| <a name="input_cors_allowed_methods"></a> [cors\_allowed\_methods](#input\_cors\_allowed\_methods) | Specifies which methods are allowed. Can be GET, PUT, POST, DELETE or HEAD. | `list` | <pre>[<br/>  "GET"<br/>]</pre> | no |
| <a name="input_cors_allowed_origins"></a> [cors\_allowed\_origins](#input\_cors\_allowed\_origins) | Specifies which origins are allowed. | `list` | <pre>[<br/>  "*"<br/>]</pre> | no |
| <a name="input_cors_expose_headers"></a> [cors\_expose\_headers](#input\_cors\_expose\_headers) | Specifies expose header in the response. | `list` | `[]` | no |
| <a name="input_cors_max_age_seconds"></a> [cors\_max\_age\_seconds](#input\_cors\_max\_age\_seconds) | Specifies time in seconds that browser can cache the response for a preflight request. | `string` | `"3000"` | no |
| <a name="input_create_lifecycle_policy"></a> [create\_lifecycle\_policy](#input\_create\_lifecycle\_policy) | States whether the module autocreates the lifecycle policy | `bool` | `true` | no |
| <a name="input_datasync_source_access_enabled"></a> [datasync\_source\_access\_enabled](#input\_datasync\_source\_access\_enabled) | Enable DataSync source access policy and source KMS decrypt key-policy access | `bool` | `false` | no |
| <a name="input_datasync_source_role_arns"></a> [datasync\_source\_role\_arns](#input\_datasync\_source\_role\_arns) | Optional IAM role ARNs used by DataSync to read from this source bucket. When set, the module grants source bucket read and source KMS decrypt key-policy access | `list(string)` | `[]` | no |
| <a name="input_email_addresses"></a> [email\_addresses](#input\_email\_addresses) | A list of email addresses for key rotation notifications. | `list` | `[]` | no |
| <a name="input_enforce_kms_key_use"></a> [enforce\_kms\_key\_use](#input\_enforce\_kms\_key\_use) | Whether or not to require a PutObject request to specify the KMS key id that was created. Defaults to true. Should only be set to false to emulate the behaviour of v0.x of the module and only until the tenants have changed their code to specify the KMS key id in their requests | `bool` | `true` | no |
| <a name="input_enforce_tls"></a> [enforce\_tls](#input\_enforce\_tls) | Specifies if the bucket will be enforce a TLS bucket policy | `bool` | `true` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | The environment the S3 is running in i.e. dev, prod etc | `any` | n/a | yes |
| <a name="input_expire_noncurrent_versions"></a> [expire\_noncurrent\_versions](#input\_expire\_noncurrent\_versions) | Allow expiration/retention rules to apply for all non-current version objects | `bool` | `true` | no |
| <a name="input_iam_user_policy_name"></a> [iam\_user\_policy\_name](#input\_iam\_user\_policy\_name) | The policy name of attached to the user | `string` | n/a | yes |
| <a name="input_key_rotation"></a> [key\_rotation](#input\_key\_rotation) | Enable email notifications for old IAM keys. | `bool` | `true` | no |
| <a name="input_kms_alias"></a> [kms\_alias](#input\_kms\_alias) | The alias name for the kms key used to encrypt and decrypt the created S3 bucket objects | `string` | `""` | no |
| <a name="input_kms_key_policy"></a> [kms\_key\_policy](#input\_kms\_key\_policy) | KMS key policy (uses a default policy if omitted) | `string` | `""` | no |
| <a name="input_lifecycle_abort_multipart_upload_enabled"></a> [lifecycle\_abort\_multipart\_upload\_enabled](#input\_lifecycle\_abort\_multipart\_upload\_enabled) | Specifies Abort Multipart Uploads lifecycle rule status. | `bool` | `false` | no |
| <a name="input_lifecycle_abort_multipart_upload_object_prefix"></a> [lifecycle\_abort\_multipart\_upload\_object\_prefix](#input\_lifecycle\_abort\_multipart\_upload\_object\_prefix) | Object key prefix identifying one or more objects to which the lifecycle rule applies. | `string` | `""` | no |
| <a name="input_lifecycle_abort_multipart_upload_object_tags"></a> [lifecycle\_abort\_multipart\_upload\_object\_tags](#input\_lifecycle\_abort\_multipart\_upload\_object\_tags) | Object tags to filter on for the abort multipart upload lifecycle rule. | `map` | `{}` | no |
| <a name="input_lifecycle_days_to_abort_multipart_upload"></a> [lifecycle\_days\_to\_abort\_multipart\_upload](#input\_lifecycle\_days\_to\_abort\_multipart\_upload) | Specifies the number of days after which Amazon S3 aborts an incomplete multipart upload. | `string` | `"7"` | no |
| <a name="input_lifecycle_days_to_expiration"></a> [lifecycle\_days\_to\_expiration](#input\_lifecycle\_days\_to\_expiration) | Specifies the number of days after object creation when the object expires. | `string` | `"365"` | no |
| <a name="input_lifecycle_days_to_glacier_deep_archive_transition"></a> [lifecycle\_days\_to\_glacier\_deep\_archive\_transition](#input\_lifecycle\_days\_to\_glacier\_deep\_archive\_transition) | Specifies the number of days after object creation when it will be moved to Glacier storage. | `string` | `"180"` | no |
| <a name="input_lifecycle_days_to_glacier_transition"></a> [lifecycle\_days\_to\_glacier\_transition](#input\_lifecycle\_days\_to\_glacier\_transition) | Specifies the number of days after object creation when it will be moved to Glacier storage. | `string` | `"180"` | no |
| <a name="input_lifecycle_days_to_infrequent_storage_transition"></a> [lifecycle\_days\_to\_infrequent\_storage\_transition](#input\_lifecycle\_days\_to\_infrequent\_storage\_transition) | Specifies the number of days after object creation when it will be moved to standard infrequent access storage. | `string` | `"60"` | no |
| <a name="input_lifecycle_expiration_enabled"></a> [lifecycle\_expiration\_enabled](#input\_lifecycle\_expiration\_enabled) | Specifies expiration lifecycle rule status. | `bool` | `false` | no |
| <a name="input_lifecycle_expiration_object_prefix"></a> [lifecycle\_expiration\_object\_prefix](#input\_lifecycle\_expiration\_object\_prefix) | Object key prefix identifying one or more objects to which the lifecycle rule applies. | `string` | `""` | no |
| <a name="input_lifecycle_expiration_object_prefixes"></a> [lifecycle\_expiration\_object\_prefixes](#input\_lifecycle\_expiration\_object\_prefixes) | Optional list of prefixes for object expiration lifecycle rules | `list(string)` | `[]` | no |
| <a name="input_lifecycle_expiration_object_tags"></a> [lifecycle\_expiration\_object\_tags](#input\_lifecycle\_expiration\_object\_tags) | Object tags to filter on for the expire object lifecycle rule. | `map` | `{}` | no |
| <a name="input_lifecycle_glacier_deep_archive_object_prefix"></a> [lifecycle\_glacier\_deep\_archive\_object\_prefix](#input\_lifecycle\_glacier\_deep\_archive\_object\_prefix) | Object key prefix identifying one or more objects to which the lifecycle rule applies. | `string` | `""` | no |
| <a name="input_lifecycle_glacier_deep_archive_object_tags"></a> [lifecycle\_glacier\_deep\_archive\_object\_tags](#input\_lifecycle\_glacier\_deep\_archive\_object\_tags) | Object tags to filter on for the transition to glacier lifecycle rule. | `map` | `{}` | no |
| <a name="input_lifecycle_glacier_deep_archive_transition_enabled"></a> [lifecycle\_glacier\_deep\_archive\_transition\_enabled](#input\_lifecycle\_glacier\_deep\_archive\_transition\_enabled) | Specifies Glacier Deep Archive transition lifecycle rule status. | `bool` | `false` | no |
| <a name="input_lifecycle_glacier_object_prefix"></a> [lifecycle\_glacier\_object\_prefix](#input\_lifecycle\_glacier\_object\_prefix) | Object key prefix identifying one or more objects to which the lifecycle rule applies. | `string` | `""` | no |
| <a name="input_lifecycle_glacier_object_tags"></a> [lifecycle\_glacier\_object\_tags](#input\_lifecycle\_glacier\_object\_tags) | Object tags to filter on for the transition to glacier lifecycle rule. | `map` | `{}` | no |
| <a name="input_lifecycle_glacier_transition_enabled"></a> [lifecycle\_glacier\_transition\_enabled](#input\_lifecycle\_glacier\_transition\_enabled) | Specifies Glacier transition lifecycle rule status. | `bool` | `false` | no |
| <a name="input_lifecycle_infrequent_storage_object_prefix"></a> [lifecycle\_infrequent\_storage\_object\_prefix](#input\_lifecycle\_infrequent\_storage\_object\_prefix) | Object key prefix identifying one or more objects to which the lifecycle rule applies. | `string` | `""` | no |
| <a name="input_lifecycle_infrequent_storage_object_tags"></a> [lifecycle\_infrequent\_storage\_object\_tags](#input\_lifecycle\_infrequent\_storage\_object\_tags) | Object tags to filter on for the transition to infrequent storage lifecycle rule. | `map` | `{}` | no |
| <a name="input_lifecycle_infrequent_storage_transition_enabled"></a> [lifecycle\_infrequent\_storage\_transition\_enabled](#input\_lifecycle\_infrequent\_storage\_transition\_enabled) | Specifies infrequent storage transition lifecycle rule status. | `bool` | `false` | no |
| <a name="input_log_target_bucket"></a> [log\_target\_bucket](#input\_log\_target\_bucket) | The S3 bucket that access logs should be sent to. | `string` | `""` | no |
| <a name="input_log_target_prefix"></a> [log\_target\_prefix](#input\_log\_target\_prefix) | The object prefix for access logs | `string` | `""` | no |
| <a name="input_logging_enabled"></a> [logging\_enabled](#input\_logging\_enabled) | Specifies whether server access logging is enabled or not. | `bool` | `false` | no |
| <a name="input_name"></a> [name](#input\_name) | A descriptive name for the S3 instance | `any` | n/a | yes |
| <a name="input_number_of_users"></a> [number\_of\_users](#input\_number\_of\_users) | The number of user to generate credentials for | `number` | `1` | no |
| <a name="input_ownership_controls"></a> [ownership\_controls](#input\_ownership\_controls) | Ownership controls for the writer must be defined by default | `string` | `"ObjectWriter"` | no |
| <a name="input_ownership_controls_object"></a> [ownership\_controls\_object](#input\_ownership\_controls\_object) | control\_object\_ownership needs to be set to true | `bool` | `true` | no |
| <a name="input_replication_delete_marker_replication_status"></a> [replication\_delete\_marker\_replication\_status](#input\_replication\_delete\_marker\_replication\_status) | Delete marker replication status. Defaults to Enabled so deletes mirror by default. Valid values are Enabled or Disabled | `string` | `"Enabled"` | no |
| <a name="input_replication_destination_account_id"></a> [replication\_destination\_account\_id](#input\_replication\_destination\_account\_id) | Destination AWS account ID for cross-account replication ownership takeover. Leave empty for same-account replication | `string` | `""` | no |
| <a name="input_replication_destination_bucket_arn"></a> [replication\_destination\_bucket\_arn](#input\_replication\_destination\_bucket\_arn) | ARN of the destination S3 bucket for replication | `string` | `""` | no |
| <a name="input_replication_destination_kms_key_arn"></a> [replication\_destination\_kms\_key\_arn](#input\_replication\_destination\_kms\_key\_arn) | Destination KMS key ARN for replicated objects. Required when replication is enabled so replicas are always written with a defined KMS key | `string` | `""` | no |
| <a name="input_replication_destination_storage_class"></a> [replication\_destination\_storage\_class](#input\_replication\_destination\_storage\_class) | Optional storage class override for replicated objects. When omitted, source object storage class is preserved where supported | `string` | `null` | no |
| <a name="input_replication_enabled"></a> [replication\_enabled](#input\_replication\_enabled) | Enable cross-bucket replication from this bucket to a destination bucket | `bool` | `false` | no |
| <a name="input_replication_metrics_enabled"></a> [replication\_metrics\_enabled](#input\_replication\_metrics\_enabled) | Enable S3 replication metrics and event notifications | `bool` | `false` | no |
| <a name="input_replication_prefix"></a> [replication\_prefix](#input\_replication\_prefix) | Object prefix to replicate. Leave empty to replicate all objects | `string` | `""` | no |
| <a name="input_replication_replica_modifications_enabled"></a> [replication\_replica\_modifications\_enabled](#input\_replication\_replica\_modifications\_enabled) | Enable replica modification sync for advanced bidirectional-style replication scenarios | `bool` | `false` | no |
| <a name="input_replication_report_bucket_arn"></a> [replication\_report\_bucket\_arn](#input\_replication\_report\_bucket\_arn) | Optional S3 bucket ARN for S3 Batch Replication completion reports. Defaults to replication\_destination\_bucket\_arn | `string` | `""` | no |
| <a name="input_replication_report_bucket_kms_key_arn"></a> [replication\_report\_bucket\_kms\_key\_arn](#input\_replication\_report\_bucket\_kms\_key\_arn) | Optional KMS key ARN for encrypting S3 Batch Replication reports written to replication\_report\_bucket\_arn. Defaults to replication\_destination\_kms\_key\_arn | `string` | `""` | no |
| <a name="input_replication_source_kms_key_arns"></a> [replication\_source\_kms\_key\_arns](#input\_replication\_source\_kms\_key\_arns) | Optional additional source KMS key ARNs for replicating SSE-KMS objects when the source bucket contains objects encrypted with keys other than the module-managed bucket key | `list(string)` | `[]` | no |
| <a name="input_replication_time_control_enabled"></a> [replication\_time\_control\_enabled](#input\_replication\_time\_control\_enabled) | Enable S3 Replication Time Control. Requires replication\_metrics\_enabled | `bool` | `false` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map` | `{}` | no |
| <a name="input_transition_noncurrent_versions"></a> [transition\_noncurrent\_versions](#input\_transition\_noncurrent\_versions) | Allow lifecycle rules to apply for all non-current version objects | `bool` | `true` | no |
| <a name="input_versioning_enabled"></a> [versioning\_enabled](#input\_versioning\_enabled) | If versioning is set for buckets in case of accidental deletion; deprecated - use versioning\_status instead | `bool` | `false` | no |
| <a name="input_versioning_status"></a> [versioning\_status](#input\_versioning\_status) | The versioning status for the bucket - valid values are: Enabled, Disabled and Suspended | `string` | `""` | no |
| <a name="input_website_error_document"></a> [website\_error\_document](#input\_website\_error\_document) | The path to the document to return in case of a 4XX error for static website hosting | `string` | `"error.html"` | no |
| <a name="input_website_hosting"></a> [website\_hosting](#input\_website\_hosting) | Specifies if the bucket will be used for static website hosting | `bool` | `false` | no |
| <a name="input_website_index_document"></a> [website\_index\_document](#input\_website\_index\_document) | The path of index document when requests are made for static website hosting | `string` | `"index.html"` | no |
| <a name="input_whitelist_ip"></a> [whitelist\_ip](#input\_whitelist\_ip) | Whitelisted ip allowed to access the created s3 bucket (note: this allows all by default) | `list` | `[]` | no |
| <a name="input_whitelist_vpc"></a> [whitelist\_vpc](#input\_whitelist\_vpc) | Whitelisted vpc allowed to access the created s3 bucket | `list` | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_s3_bucket_arn"></a> [s3\_bucket\_arn](#output\_s3\_bucket\_arn) | ARN of generated S3 bucket |
| <a name="output_s3_bucket_id"></a> [s3\_bucket\_id](#output\_s3\_bucket\_id) | ID of generated S3 bucket |
| <a name="output_s3_bucket_kms_key"></a> [s3\_bucket\_kms\_key](#output\_s3\_bucket\_kms\_key) | KMS Key ID of the generated bucket |
| <a name="output_s3_bucket_kms_key_arn"></a> [s3\_bucket\_kms\_key\_arn](#output\_s3\_bucket\_kms\_key\_arn) | KMS Key ARN of the generated bucket |
<!-- END_TF_DOCS -->