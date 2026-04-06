data "aws_iam_policy_document" "gitlab_deployer_assume_role" {
  for_each = var.platform == "gitlab" ? var.account_repo_map : {}

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.this[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "gitlab.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "gitlab.com:sub"
      values   = ["project_path:${var.namespace}/${each.value.repo}:ref_type:branch:ref:${each.value.branch}"]
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

data "aws_iam_policy_document" "gitlab_planner_assume_role" {
  for_each = var.platform == "gitlab" ? var.account_repo_map : {}

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.this[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "gitlab.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "gitlab.com:sub"
      values   = ["project_path:${var.namespace}/${each.value.repo}:*"]
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
