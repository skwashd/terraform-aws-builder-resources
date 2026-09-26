# Existing Bitbucket Pipelines trust policy behaviour, unchanged by this
# feature. Bitbucket is the one platform that already reads
# local.oidc_provider_host / local.oidc_audience instead of hardcoding them,
# and it uses a separate branchName claim rather than embedding the branch
# in sub.

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
  platform  = "bitbucket"
  namespace = "11111111-1111-1111-1111-111111111111"
  tags      = { ManagedBy = "terraform" }

  account_repo_map = {
    "111111111111" = {
      repo   = "22222222-2222-2222-2222-222222222222"
      branch = "main"
    }
  }
}

run "deployer_matches_repo_uuid_and_branch_name_claim" {
  command = plan

  assert {
    condition = anytrue([
      for c in data.aws_iam_policy_document.bitbucket_deployer_assume_role["111111111111"].statement[0].condition :
      c.test == "StringLike" &&
      c.variable == "api.bitbucket.org/2.0/workspaces/11111111-1111-1111-1111-111111111111/pipelines-config/identity/oidc:sub" &&
      toset(c.values) == toset(["{22222222-2222-2222-2222-222222222222}:*"])
    ])
    error_message = "Bitbucket deployer sub must be {repo-uuid}:* when no env is set."
  }

  assert {
    condition = anytrue([
      for c in data.aws_iam_policy_document.bitbucket_deployer_assume_role["111111111111"].statement[0].condition :
      c.test == "StringEquals" &&
      c.variable == "api.bitbucket.org/2.0/workspaces/11111111-1111-1111-1111-111111111111/pipelines-config/identity/oidc:branchName" &&
      toset(c.values) == toset(["main"])
    ])
    error_message = "Bitbucket deployer must add a branchName condition when branch is set."
  }

  assert {
    condition = anytrue([
      for c in data.aws_iam_policy_document.bitbucket_deployer_assume_role["111111111111"].statement[0].condition :
      c.test == "StringEquals" &&
      c.variable == "api.bitbucket.org/2.0/workspaces/11111111-1111-1111-1111-111111111111/pipelines-config/identity/oidc:aud" &&
      toset(c.values) == toset(["ari:cloud:bitbucket::workspace/11111111-1111-1111-1111-111111111111"])
    ])
    error_message = "Bitbucket aud must default to the workspace ARI derived from namespace."
  }
}

run "env_variant_omits_branch_name_condition" {
  command = plan

  variables {
    account_repo_map = {
      "111111111111" = {
        repo = "22222222-2222-2222-2222-222222222222"
        env  = "production"
      }
    }
  }

  assert {
    condition = anytrue([
      for c in data.aws_iam_policy_document.bitbucket_deployer_assume_role["111111111111"].statement[0].condition :
      c.test == "StringLike" && toset(c.values) == toset(["{22222222-2222-2222-2222-222222222222}:{production}:*"])
    ])
    error_message = "Bitbucket deployer sub must be {repo-uuid}:{env}:* when env is set."
  }

  assert {
    condition = length([
      for c in data.aws_iam_policy_document.bitbucket_deployer_assume_role["111111111111"].statement[0].condition :
      c if endswith(c.variable, ":branchName")
    ]) == 0
    error_message = "No branchName condition should be present when branch is not set."
  }
}

run "planner_matches_any_ref_no_branch_name" {
  command = plan

  assert {
    condition = anytrue([
      for c in data.aws_iam_policy_document.bitbucket_planner_assume_role["111111111111"].statement[0].condition :
      c.test == "StringLike" && toset(c.values) == toset(["{22222222-2222-2222-2222-222222222222}:*"])
    ])
    error_message = "Bitbucket planner must trust any ref of the repo UUID."
  }

  assert {
    condition = length([
      for c in data.aws_iam_policy_document.bitbucket_planner_assume_role["111111111111"].statement[0].condition :
      c if endswith(c.variable, ":branchName")
    ]) == 0
    error_message = "Bitbucket planner must never add a branchName condition."
  }
}

run "override_provider_config_changes_audience_and_host" {
  command = plan

  variables {
    override_provider_config = {
      oidc_audience = "ari:cloud:bitbucket::workspace/custom-override"
    }
  }

  assert {
    condition = anytrue([
      for c in data.aws_iam_policy_document.bitbucket_deployer_assume_role["111111111111"].statement[0].condition :
      c.test == "StringEquals" && strcontains(c.variable, ":aud") && toset(c.values) == toset(["ari:cloud:bitbucket::workspace/custom-override"])
    ])
    error_message = "override_provider_config.oidc_audience must flow into the aud condition."
  }
}
