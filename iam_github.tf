data "aws_iam_policy_document" "github_deployer_assume_role" {
  for_each = var.platform == "github" ? var.account_repo_map : {}

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.this[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        each.value.env != null
        ? "repo:${var.namespace}/${each.value.repo}:environment:${each.value.env}"
        : "repo:${var.namespace}/${each.value.repo}:ref:refs/heads/${each.value.branch}"
      ]
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
  for_each = var.platform == "github" ? var.account_repo_map : {}

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.this[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.namespace}/${each.value.repo}:*"]
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
