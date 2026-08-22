# Existing deployer/planner IAM role and permission-policy behaviour,
# unrelated to OIDC subjects but exercised here for comprehensive coverage.
# Role name and max_session_duration are config arguments, not computed
# attributes, so -- like the statement/condition blocks used elsewhere in
# this suite -- they stay known at plan time even though the role itself is
# not yet created.

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
  tags      = { ManagedBy = "terraform", Team = "platform" }

  account_repo_map = {
    "111111111111" = { repo = "infra", branch = "main" }
    "cloudflare"   = { repo = "infra-cloudflare", branch = "main" }
  }
}

run "role_names_and_session_durations" {
  command = plan

  assert {
    condition     = aws_iam_role.deployer["111111111111"].name == "TerraformDeployer-111111111111"
    error_message = "Deployer role name must be TerraformDeployer-<key>."
  }

  assert {
    condition     = aws_iam_role.planner["111111111111"].name == "TerraformPlanner-111111111111"
    error_message = "Planner role name must be TerraformPlanner-<key>."
  }

  assert {
    condition     = aws_iam_role.deployer["111111111111"].max_session_duration == 7200
    error_message = "Deployer max_session_duration must be 7200 seconds."
  }

  assert {
    condition     = aws_iam_role.planner["111111111111"].max_session_duration == 3600
    error_message = "Planner max_session_duration must be 3600 seconds."
  }

  assert {
    condition     = aws_iam_role.deployer["111111111111"].tags == tomap({ ManagedBy = "terraform", Team = "platform" })
    error_message = "Role tags must be passed straight through from var.tags."
  }

  assert {
    condition     = aws_iam_policy.deployer["cloudflare"].name == "TerraformDeployer-cloudflare"
    error_message = "A non-account-id key must still get a named policy and role."
  }
}

run "cross_account_assume_role_only_for_12_digit_keys" {
  command = plan

  assert {
    condition = contains(
      data.aws_iam_policy_document.deployer["111111111111"].statement[0].resources,
      "arn:aws:iam::111111111111:role/TerraformDeployer"
    )
    error_message = "An account-id key must get the cross-account TerraformDeployer permission."
  }

  assert {
    condition = contains(
      data.aws_iam_policy_document.planner["111111111111"].statement[0].resources,
      "arn:aws:iam::111111111111:role/TerraformPlanner"
    )
    error_message = "An account-id key must get the cross-account TerraformPlanner permission."
  }

  assert {
    condition     = length(data.aws_iam_policy_document.deployer["cloudflare"].statement) == 3
    error_message = "A non-account-id key must omit the cross-account assume-role statement entirely."
  }
}

run "per_entry_and_global_additional_role_arns_merge" {
  command = plan

  variables {
    additional_deployer_role_arns = ["arn:aws:iam::999999999999:role/global-deployer"]
    additional_planner_role_arns  = ["arn:aws:iam::999999999999:role/global-planner"]
    account_repo_map = {
      "111111111111" = {
        repo               = "infra"
        branch             = "main"
        deployer_role_arns = ["arn:aws:iam::888888888888:role/per-entry-deployer"]
        planner_role_arns  = ["arn:aws:iam::888888888888:role/per-entry-planner"]
      }
    }
  }

  assert {
    condition = toset(data.aws_iam_policy_document.deployer["111111111111"].statement[0].resources) == toset([
      "arn:aws:iam::111111111111:role/TerraformDeployer",
      "arn:aws:iam::888888888888:role/per-entry-deployer",
      "arn:aws:iam::999999999999:role/global-deployer",
    ])
    error_message = "Deployer resources must merge the account-id role, the per-entry ARNs, and the global additional ARNs."
  }

  assert {
    condition = toset(data.aws_iam_policy_document.planner["111111111111"].statement[0].resources) == toset([
      "arn:aws:iam::111111111111:role/TerraformPlanner",
      "arn:aws:iam::888888888888:role/per-entry-planner",
      "arn:aws:iam::999999999999:role/global-planner",
    ])
    error_message = "Planner resources must merge the account-id role, the per-entry ARNs, and the global additional ARNs."
  }
}
