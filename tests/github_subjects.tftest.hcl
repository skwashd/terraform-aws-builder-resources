# Pure-variable derivation of GitHub OIDC subject/claim conditions.
# output.github_oidc_conditions depends only on variables (no resource
# reference), so it is fully known at plan time. A real provider with static
# fake credentials is used rather than mock_provider: aws_iam_policy_document
# renders entirely client-side (no API calls), and unlike mock_provider's
# random placeholder strings, an *unknown* value here does not trip the AWS
# provider's JSON validation on aws_kms_key/aws_s3_bucket_policy, so no
# provider-side computed attribute needs to be worked around.
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
    "111111111111" = {
      repo   = "infra"
      branch = "main"
    }
    "222222222222" = {
      repo = "infra-env"
      env  = "production"
    }
  }
}

run "defaults_trust_both_formats_and_wildcard_ids" {
  command = plan

  assert {
    condition = output.github_oidc_conditions["111111111111"].deployer_subs == [
      "repo:acme/infra:ref:refs/heads/main",
      "repo:acme@*/infra@*:ref:refs/heads/main",
    ]
    error_message = "A branch deployer must trust the legacy and the wildcarded immutable subject."
  }

  assert {
    condition = output.github_oidc_conditions["222222222222"].deployer_subs == [
      "repo:acme/infra-env:environment:production",
      "repo:acme@*/infra-env@*:environment:production",
    ]
    error_message = "An environment deployer must trust the legacy and the wildcarded immutable subject."
  }

  assert {
    condition = output.github_oidc_conditions["111111111111"].planner_subs == [
      "repo:acme/infra:*",
      "repo:acme@*/infra@*:*",
    ]
    error_message = "A planner must trust any ref of the repository in both subject formats."
  }

  assert {
    condition     = output.github_oidc_conditions["111111111111"].claims == { repository = "acme/infra" }
    error_message = "Without namespace_id/repo_id, only the repository claim may be anchored."
  }
}

run "subjects_are_disjoint" {
  command = plan

  # The immutable subject always has "@" where the legacy subject has "/", and
  # "@" cannot appear in a GitHub owner or repo name, so no token can ever
  # satisfy both patterns.
  assert {
    condition = alltrue(flatten([
      for key, subs in output.github_oidc_conditions : [
        for s in subs.deployer_subs : startswith(s, "repo:acme@") != startswith(s, "repo:acme/")
      ]
    ]))
    error_message = "Each deployer subject must be unambiguously legacy or immutable, never both."
  }
}

run "real_ids_remove_every_wildcard_and_add_claim_anchors" {
  command = plan

  variables {
    namespace_id = "123456"
    account_repo_map = {
      "111111111111" = {
        repo    = "infra"
        repo_id = "456789"
        branch  = "main"
      }
    }
  }

  assert {
    condition = output.github_oidc_conditions["111111111111"].deployer_subs == [
      "repo:acme/infra:ref:refs/heads/main",
      "repo:acme@123456/infra@456789:ref:refs/heads/main",
    ]
    error_message = "Supplied IDs must be substituted into the immutable subject."
  }

  assert {
    condition     = !strcontains(join(",", output.github_oidc_conditions["111111111111"].deployer_subs), "*")
    error_message = "No wildcard may remain once both namespace_id and repo_id are supplied."
  }

  assert {
    condition = output.github_oidc_conditions["111111111111"].claims == {
      repository          = "acme/infra"
      repository_owner_id = "123456"
      repository_id       = "456789"
    }
    error_message = "Supplying both IDs must add both ID claim anchors alongside repository."
  }
}

run "namespace_id_alone_anchors_the_owner_but_not_the_repo" {
  command = plan

  variables {
    namespace_id = "123456"
    account_repo_map = {
      "111111111111" = { repo = "infra", branch = "main" }
    }
  }

  assert {
    condition     = output.github_oidc_conditions["111111111111"].deployer_subs[1] == "repo:acme@123456/infra@*:ref:refs/heads/main"
    error_message = "repo_id should stay wildcarded when not supplied."
  }

  assert {
    condition     = output.github_oidc_conditions["111111111111"].claims == { repository = "acme/infra", repository_owner_id = "123456" }
    error_message = "Only namespace_id was supplied, so only repository_owner_id should be anchored alongside repository."
  }
}

run "immutable_only_drops_the_legacy_subject_for_both_roles" {
  command = plan

  variables {
    namespace_id        = "123456"
    immutable_subs_only = true
    account_repo_map = {
      "111111111111" = { repo = "infra", repo_id = "456789", branch = "main" }
      "222222222222" = { repo = "infra-env", repo_id = "456790", env = "production" }
    }
  }

  assert {
    condition     = output.github_oidc_conditions["111111111111"].deployer_subs == ["repo:acme@123456/infra@456789:ref:refs/heads/main"]
    error_message = "immutable_subs_only must emit the immutable branch subject and nothing else."
  }

  assert {
    condition     = output.github_oidc_conditions["222222222222"].deployer_subs == ["repo:acme@123456/infra-env@456790:environment:production"]
    error_message = "immutable_subs_only must emit the immutable environment subject and nothing else."
  }

  assert {
    condition     = length(output.github_oidc_conditions["111111111111"].planner_subs) == 1
    error_message = "immutable_subs_only must apply to the planner as well as the deployer."
  }
}

run "env_takes_precedence_over_branch" {
  command = plan

  variables {
    account_repo_map = {
      "111111111111" = { repo = "infra", branch = "main", env = "production" }
    }
  }

  assert {
    condition     = output.github_oidc_conditions["111111111111"].deployer_subs[0] == "repo:acme/infra:environment:production"
    error_message = "When both branch and env are set, env must win in the deployer subject (existing behaviour, unchanged by this feature)."
  }
}
