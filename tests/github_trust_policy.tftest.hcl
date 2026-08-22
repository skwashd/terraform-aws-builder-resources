# Structural coverage of the actual github_deployer_assume_role /
# github_planner_assume_role data sources, as opposed to
# github_subjects.tftest.hcl which only exercises the github_oidc_conditions
# output. This proves the output's values are the same ones actually wired
# into the condition blocks.
#
# aws_iam_policy_document.*.json is a computed attribute rendered by the
# provider from aws_iam_openid_connect_provider.this[0].arn, which is unknown
# at plan time for a not-yet-created resource -- override_resource with
# override_during=plan does not change this, confirmed by direct
# reproduction against a minimal config. The statement/condition *blocks*
# are a different matter: they are argument echoes of the data source's own
# config, not values read back from the provider, so they stay known at plan
# even while .json is deferred to apply. Assert on those instead.
#
# The provider schema types statement.actions and condition.values as
# set(string), not list(string), so "==" against a list/tuple literal
# silently returns false (with a "different types" warning) rather than
# comparing elements. Wrap both sides in toset() throughout this file.

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
  platform     = "github"
  namespace    = "acme"
  namespace_id = "123456"
  tags         = { ManagedBy = "terraform" }

  account_repo_map = {
    "111111111111" = { repo = "infra", repo_id = "456789", branch = "main" }
  }
}

run "deployer_statement_carries_subjects_and_claims" {
  command = plan

  assert {
    condition = anytrue([
      for c in data.aws_iam_policy_document.github_deployer_assume_role["111111111111"].statement[0].condition :
      c.test == "StringLike" && c.variable == "token.actions.githubusercontent.com:sub" && toset(c.values) == toset([
        "repo:acme/infra:ref:refs/heads/main",
        "repo:acme@123456/infra@456789:ref:refs/heads/main",
      ])
    ])
    error_message = "The sub condition must carry both subject values in one condition block."
  }

  assert {
    condition = anytrue([
      for c in data.aws_iam_policy_document.github_deployer_assume_role["111111111111"].statement[0].condition :
      c.test == "StringEquals" && c.variable == "token.actions.githubusercontent.com:repository" && toset(c.values) == toset(["acme/infra"])
    ])
    error_message = "The repository claim must be anchored."
  }

  assert {
    condition = anytrue([
      for c in data.aws_iam_policy_document.github_deployer_assume_role["111111111111"].statement[0].condition :
      c.test == "StringEquals" && c.variable == "token.actions.githubusercontent.com:repository_owner_id" && toset(c.values) == toset(["123456"])
    ])
    error_message = "The repository_owner_id claim must be anchored when namespace_id is supplied."
  }

  assert {
    condition = anytrue([
      for c in data.aws_iam_policy_document.github_deployer_assume_role["111111111111"].statement[0].condition :
      c.test == "StringEquals" && c.variable == "token.actions.githubusercontent.com:repository_id" && toset(c.values) == toset(["456789"])
    ])
    error_message = "The repository_id claim must be anchored when repo_id is supplied."
  }

  assert {
    condition = anytrue([
      for c in data.aws_iam_policy_document.github_deployer_assume_role["111111111111"].statement[0].condition :
      c.test == "StringEquals" && c.variable == "token.actions.githubusercontent.com:aud" && toset(c.values) == toset(["sts.amazonaws.com"])
    ])
    error_message = "The aud condition must be preserved."
  }

  assert {
    condition     = length(data.aws_iam_policy_document.github_planner_assume_role["111111111111"].statement) == 1
    error_message = "No additional_trust_principal_arns were set, so only one statement should be present."
  }
}

run "wildcarded_defaults_omit_id_claims" {
  command = plan

  variables {
    namespace_id = "*"
    account_repo_map = {
      "111111111111" = { repo = "infra", branch = "main" }
    }
  }

  assert {
    condition = length([
      for c in data.aws_iam_policy_document.github_deployer_assume_role["111111111111"].statement[0].condition :
      c if c.test == "StringEquals" && strcontains(c.variable, "repository_")
    ]) == 0
    error_message = "With namespace_id and repo_id both wildcarded, no ID claim should be anchored."
  }

  assert {
    condition = anytrue([
      for c in data.aws_iam_policy_document.github_deployer_assume_role["111111111111"].statement[0].condition :
      c.test == "StringEquals" && c.variable == "token.actions.githubusercontent.com:repository" && toset(c.values) == toset(["acme/infra"])
    ])
    error_message = "The repository claim has no wildcard concept and must always be anchored."
  }
}

run "additional_trust_principal_arns_add_a_second_statement" {
  command = plan

  variables {
    additional_trust_principal_arns = ["arn:aws:iam::999999999999:role/ci-tester"]
    account_repo_map = {
      "111111111111" = { repo = "infra", branch = "main" }
    }
  }

  assert {
    condition     = length(data.aws_iam_policy_document.github_deployer_assume_role["111111111111"].statement) == 2
    error_message = "additional_trust_principal_arns must add a second sts:AssumeRole statement."
  }

  assert {
    condition     = toset(data.aws_iam_policy_document.github_deployer_assume_role["111111111111"].statement[1].actions) == toset(["sts:AssumeRole"])
    error_message = "The additional trust statement must use sts:AssumeRole, not AssumeRoleWithWebIdentity."
  }
}
