data "aws_iam_policy_document" "bitbucket_deployer_assume_role" {
  for_each = var.platform == "bitbucket" ? var.account_repo_map : {}

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
      values   = ["${each.value.repo}:*"]
    }

    dynamic "condition" {
      for_each = each.value.branch != null ? [1] : []
      content {
        test     = "StringEquals"
        variable = "${local.oidc_provider_host}:branchName"
        values   = [each.value.branch]
      }
    }

    dynamic "condition" {
      for_each = each.value.env != null ? [1] : []
      content {
        test     = "StringEquals"
        variable = "${local.oidc_provider_host}:deploymentEnvironmentUuid"
        values   = [each.value.env]
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

data "aws_iam_policy_document" "bitbucket_planner_assume_role" {
  for_each = var.platform == "bitbucket" ? var.account_repo_map : {}

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
      values   = ["${each.value.repo}:*"]
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
