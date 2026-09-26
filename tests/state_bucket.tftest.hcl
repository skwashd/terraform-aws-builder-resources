# Existing S3 state bucket / KMS behaviour, unrelated to OIDC subjects but
# exercised here for comprehensive coverage. All assertions target
# configured arguments (bucket name built from overridden data sources,
# resource block config), not computed attributes like ARNs, which stay
# unknown at plan for not-yet-created resources.

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_requesting_account_id  = true
}

override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "123456789012" }
}

override_data {
  target = data.aws_region.current
  values = { region = "us-east-1" }
}

variables {
  platform  = "github"
  namespace = "acme"
  tags      = { ManagedBy = "terraform" }

  account_repo_map = {
    "111111111111" = { repo = "infra", branch = "main" }
  }
}

run "bucket_name_and_hardening" {
  command = plan

  assert {
    condition     = aws_s3_bucket.state.bucket == "tfstate-123456789012-us-east-1-an"
    error_message = "State bucket name must be tfstate-<account_id>-<region>-an."
  }

  assert {
    condition     = aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled"
    error_message = "State bucket must have versioning enabled."
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.state.block_public_acls,
      aws_s3_bucket_public_access_block.state.block_public_policy,
      aws_s3_bucket_public_access_block.state.ignore_public_acls,
      aws_s3_bucket_public_access_block.state.restrict_public_buckets,
    ])
    error_message = "State bucket must block all public access."
  }

  assert {
    condition = anytrue([
      for r in aws_s3_bucket_server_side_encryption_configuration.state.rule :
      anytrue([for d in r.apply_server_side_encryption_by_default : d.sse_algorithm == "aws:kms"])
    ])
    error_message = "State bucket must be encrypted with the module's KMS key."
  }

  assert {
    condition     = aws_kms_key.s3_state.enable_key_rotation == true
    error_message = "The state KMS key must have rotation enabled."
  }
}

run "logging_disabled_by_default" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket_logging.state) == 0
    error_message = "Access logging must be disabled when logging_bucket is not set."
  }
}

run "logging_bucket_enables_access_logging" {
  command = plan

  variables {
    logging_bucket = "my-existing-access-logs-bucket"
  }

  assert {
    condition     = length(aws_s3_bucket_logging.state) == 1
    error_message = "Setting logging_bucket must create the logging resource."
  }

  assert {
    condition     = aws_s3_bucket_logging.state[0].target_bucket == "my-existing-access-logs-bucket"
    error_message = "Access logs must target the supplied bucket."
  }
}
