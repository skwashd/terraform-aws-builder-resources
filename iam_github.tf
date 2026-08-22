locals {
  github_entries     = var.platform == "github" ? var.account_repo_map : {}
  include_legacy_sub = !var.immutable_subs_only

  # Component parts of the GitHub sub claim, one entry per account_repo_map key.
  #
  #   legacy     repo:OWNER/REPO:<tail>
  #   immutable  repo:OWNER@OWNER-ID/REPO@REPO-ID:<tail>
  #
  # GitHub picked "@" as the separator because it cannot appear in an owner or a
  # repository name, so no token can ever match both forms. Repositories created
  # after 2026-07-15, and any repository renamed or transferred after that date,
  # emit the immutable form. A repository emits one form, never both.
  github_subs = {
    for key, entry in local.github_entries : key => {
      legacy_repo    = "repo:${var.namespace}/${entry.repo}"
      immutable_repo = "repo:${var.namespace}@${var.namespace_id}/${entry.repo}@${entry.repo_id}"
      deployer_tail  = entry.env != null ? "environment:${entry.env}" : "ref:refs/heads/${entry.branch}"
    }
  }

  # Values for the sub condition. IAM ORs the values of a single condition key, so
  # one role trusts a repository whether or not it has moved to immutable claims.
  github_sub_values = {
    for key, parts in local.github_subs : key => {
      deployer = concat(
        local.include_legacy_sub ? ["${parts.legacy_repo}:${parts.deployer_tail}"] : [],
        ["${parts.immutable_repo}:${parts.deployer_tail}"],
      )
      planner = concat(
        local.include_legacy_sub ? ["${parts.legacy_repo}:*"] : [],
        ["${parts.immutable_repo}:*"],
      )
    }
  }

  # Claims that do not change with the subject format. repository is always
  # known; the ID claims are only asserted once a real ID is supplied, since
  # under StringEquals "*" is a literal and would match nothing.
  github_claims = {
    for key, entry in local.github_entries : key => merge(
      { repository = "${var.namespace}/${entry.repo}" },
      var.namespace_id != "*" ? { repository_owner_id = var.namespace_id } : {},
      entry.repo_id != "*" ? { repository_id = entry.repo_id } : {},
    )
  }
}

data "aws_iam_policy_document" "github_deployer_assume_role" {
  for_each = local.github_entries

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.this[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:aud"
      values   = [local.oidc_audience]
    }

    condition {
      test     = "StringLike"
      variable = "${local.oidc_provider_host}:sub"
      values   = local.github_sub_values[each.key].deployer
    }

    dynamic "condition" {
      for_each = local.github_claims[each.key]
      content {
        test     = "StringEquals"
        variable = "${local.oidc_provider_host}:${condition.key}"
        values   = [condition.value]
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.additional_trust_principal_arns) > 0 ? [1] : []
    content {
      actions = ["sts:AssumeRole"]
      principals {
        type        = "AWS"
        identifiers = var.additional_trust_principal_arns
      }
    }
  }
}

data "aws_iam_policy_document" "github_planner_assume_role" {
  for_each = local.github_entries

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.this[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:aud"
      values   = [local.oidc_audience]
    }

    condition {
      test     = "StringLike"
      variable = "${local.oidc_provider_host}:sub"
      values   = local.github_sub_values[each.key].planner
    }

    dynamic "condition" {
      for_each = local.github_claims[each.key]
      content {
        test     = "StringEquals"
        variable = "${local.oidc_provider_host}:${condition.key}"
        values   = [condition.value]
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.additional_trust_principal_arns) > 0 ? [1] : []
    content {
      actions = ["sts:AssumeRole"]
      principals {
        type        = "AWS"
        identifiers = var.additional_trust_principal_arns
      }
    }
  }
}
