# Existing "none" platform behaviour, unchanged by this feature: plain
# sts:AssumeRole trust from additional_trust_principal_arns, no OIDC
# provider, and no repo/branch/env conditions at all. Unlike every other
# platform, none's assume-role documents have no dependency on the OIDC
# provider resource, so their .json is plan-known -- asserted directly here.

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
  platform                        = "none"
  tags                            = { ManagedBy = "terraform" }
  additional_trust_principal_arns = ["arn:aws:iam::999999999999:role/ci-tester"]

  account_repo_map = {
    "111111111111" = {}
    "cloudflare"   = {}
  }
}

run "no_oidc_provider_is_created" {
  command = plan

  assert {
    condition     = length(aws_iam_openid_connect_provider.this) == 0
    error_message = "platform=none must not create an OIDC identity provider."
  }
}

run "trust_policy_is_plain_assume_role_from_trust_principals" {
  command = plan

  assert {
    condition     = strcontains(data.aws_iam_policy_document.none_deployer_assume_role["111111111111"].json, "arn:aws:iam::999999999999:role/ci-tester")
    error_message = "none deployer trust policy must trust additional_trust_principal_arns."
  }

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.none_deployer_assume_role["111111111111"].json).Statement[0].Action == "sts:AssumeRole"
    error_message = "none platform must use plain sts:AssumeRole, not AssumeRoleWithWebIdentity."
  }

  assert {
    condition     = !can(jsondecode(data.aws_iam_policy_document.none_deployer_assume_role["111111111111"].json).Statement[0].Condition)
    error_message = "none platform must have no OIDC conditions at all."
  }

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.none_planner_assume_role["cloudflare"].json).Statement[0].Action == "sts:AssumeRole"
    error_message = "none planner trust policy must also be plain sts:AssumeRole, including for non-account-id keys."
  }
}

run "cross_account_assume_role_permission_only_for_12_digit_keys" {
  command = plan

  assert {
    condition = contains(
      data.aws_iam_policy_document.deployer["111111111111"].statement[0].resources,
      "arn:aws:iam::111111111111:role/TerraformDeployer"
    )
    error_message = "A 12-digit account-id key must get the cross-account TerraformDeployer assume-role permission."
  }

  assert {
    condition     = length(data.aws_iam_policy_document.deployer["cloudflare"].statement) == 3
    error_message = "A non-account-id key must omit the cross-account assume-role statement (S3 list/rw + KMS statements only)."
  }
}
