# Existing GitLab CI/CD trust policy behaviour, unchanged by this feature.
# See github_trust_policy.tftest.hcl for why statement/condition blocks (not
# .json) are the assertable surface at plan time, and why set(string)
# comparisons need toset() on both sides.

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
  platform  = "gitlab"
  namespace = "mygroup"
  tags      = { ManagedBy = "terraform" }

  account_repo_map = {
    "111111111111" = { repo = "myproject", branch = "main" }
  }
}

run "deployer_matches_branch_only" {
  command = plan

  assert {
    condition = anytrue([
      for c in data.aws_iam_policy_document.gitlab_deployer_assume_role["111111111111"].statement[0].condition :
      c.test == "StringLike" && c.variable == "gitlab.com:sub" &&
      toset(c.values) == toset(["project_path:mygroup/myproject:ref_type:branch:ref:main"])
    ])
    error_message = "GitLab deployer sub must be project_path:<group>/<project>:ref_type:branch:ref:<branch>."
  }

  assert {
    condition = anytrue([
      for c in data.aws_iam_policy_document.gitlab_deployer_assume_role["111111111111"].statement[0].condition :
      c.test == "StringEquals" && c.variable == "gitlab.com:aud" && toset(c.values) == toset(["sts.amazonaws.com"])
    ])
    error_message = "GitLab aud must be sts.amazonaws.com."
  }
}

run "planner_matches_any_ref" {
  command = plan

  assert {
    condition = anytrue([
      for c in data.aws_iam_policy_document.gitlab_planner_assume_role["111111111111"].statement[0].condition :
      c.test == "StringLike" && c.variable == "gitlab.com:sub" &&
      toset(c.values) == toset(["project_path:mygroup/myproject:*"])
    ])
    error_message = "GitLab planner must trust any ref of the project."
  }
}

run "additional_trust_principal_arns_add_a_second_statement" {
  command = plan

  variables {
    additional_trust_principal_arns = ["arn:aws:iam::999999999999:role/ci-tester"]
  }

  assert {
    condition     = length(data.aws_iam_policy_document.gitlab_deployer_assume_role["111111111111"].statement) == 2
    error_message = "additional_trust_principal_arns must add a second sts:AssumeRole statement for GitLab too."
  }
}

run "other_platforms_produce_no_gitlab_documents" {
  command = plan

  variables {
    platform = "github"
    account_repo_map = {
      "111111111111" = { repo = "myproject", branch = "main" }
    }
  }

  assert {
    condition     = length(data.aws_iam_policy_document.gitlab_deployer_assume_role) == 0
    error_message = "gitlab_deployer_assume_role must be empty when platform is not gitlab."
  }
}
