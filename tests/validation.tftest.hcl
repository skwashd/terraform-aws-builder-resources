# Coverage for every variable validation block, old and new.
# expect_failures requires command = plan and must name the exact variable
# whose validation block is expected to fail. A provider block is still
# needed for the runs that are expected to succeed: those proceed past
# variable validation into a full resource plan, which configures the AWS
# provider regardless of whether anything ends up asserted on.

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

run "platform_must_be_a_known_value" {
  command = plan
  variables {
    platform = "jenkins"
  }
  expect_failures = [var.platform]
}

run "namespace_required_unless_platform_is_none" {
  command = plan
  variables {
    namespace = ""
  }
  expect_failures = [var.namespace]
}

run "namespace_not_required_when_platform_is_none" {
  command = plan
  variables {
    platform                        = "none"
    namespace                       = ""
    additional_trust_principal_arns = ["arn:aws:iam::999999999999:role/ci-tester"]
    account_repo_map = {
      "111111111111" = {}
    }
  }
}

run "repo_requires_branch_or_env" {
  command = plan
  variables {
    account_repo_map = {
      "111111111111" = { repo = "infra" }
    }
  }
  expect_failures = [var.account_repo_map]
}

run "repo_required_unless_platform_is_none" {
  command = plan
  variables {
    account_repo_map = {
      "111111111111" = { branch = "main" }
    }
  }
  expect_failures = [var.account_repo_map]
}

run "gitlab_requires_branch_on_every_entry" {
  command = plan
  variables {
    platform  = "gitlab"
    namespace = "mygroup"
    account_repo_map = {
      "111111111111" = { repo = "infra", env = "production" }
    }
  }
  expect_failures = [var.account_repo_map]
}

run "additional_trust_principal_arns_required_when_platform_is_none" {
  command = plan
  variables {
    platform  = "none"
    namespace = ""
    account_repo_map = {
      "111111111111" = {}
    }
  }
  expect_failures = [var.additional_trust_principal_arns]
}

run "repo_id_must_be_numeric_or_wildcard" {
  command = plan
  variables {
    account_repo_map = {
      "111111111111" = { repo = "infra", branch = "main", repo_id = "not-a-number" }
    }
  }
  expect_failures = [var.account_repo_map]
}

run "repo_id_rejects_leading_zero" {
  command = plan
  variables {
    account_repo_map = {
      "111111111111" = { repo = "infra", branch = "main", repo_id = "0123456" }
    }
  }
  expect_failures = [var.account_repo_map]
}

run "repo_id_only_supported_on_github" {
  command = plan
  variables {
    platform  = "gitlab"
    namespace = "mygroup"
    account_repo_map = {
      "111111111111" = { repo = "infra", branch = "main", repo_id = "456789" }
    }
  }
  expect_failures = [var.account_repo_map]
}

run "namespace_id_must_be_numeric_or_wildcard" {
  command = plan
  variables {
    namespace_id = "acme"
  }
  expect_failures = [var.namespace_id]
}

run "namespace_id_rejects_leading_zero" {
  command = plan
  variables {
    namespace_id = "0123456"
  }
  expect_failures = [var.namespace_id]
}

run "namespace_id_only_supported_on_github" {
  command = plan
  variables {
    platform     = "gitlab"
    namespace    = "mygroup"
    namespace_id = "123456"
    account_repo_map = {
      "111111111111" = { repo = "infra", branch = "main" }
    }
  }
  expect_failures = [var.namespace_id]
}

run "immutable_subs_only_only_supported_on_github" {
  command = plan
  variables {
    platform            = "gitlab"
    namespace           = "mygroup"
    immutable_subs_only = true
    account_repo_map = {
      "111111111111" = { repo = "infra", branch = "main" }
    }
  }
  expect_failures = [var.immutable_subs_only]
}

run "immutable_subs_only_requires_a_pinned_namespace_id" {
  command = plan
  variables {
    immutable_subs_only = true
    account_repo_map = {
      "111111111111" = { repo = "infra", repo_id = "456789", branch = "main" }
    }
  }
  expect_failures = [var.namespace_id]
}

run "immutable_subs_only_requires_a_pinned_repo_id" {
  command = plan
  variables {
    immutable_subs_only = true
    namespace_id        = "123456"
    account_repo_map = {
      "111111111111" = { repo = "infra", branch = "main" }
    }
  }
  expect_failures = [var.account_repo_map]
}

run "immutable_subs_only_with_namespace_id_is_valid" {
  command = plan
  variables {
    immutable_subs_only = true
    namespace_id        = "123456"
    account_repo_map = {
      "111111111111" = { repo = "infra", repo_id = "456789", branch = "main" }
    }
  }
}
