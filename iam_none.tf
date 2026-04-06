data "aws_iam_policy_document" "none_deployer_assume_role" {
  for_each = var.platform == "none" ? var.account_repo_map : {}

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = var.additional_trust_principal_arns
    }
  }
}

data "aws_iam_policy_document" "none_planner_assume_role" {
  for_each = var.platform == "none" ? var.account_repo_map : {}

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = var.additional_trust_principal_arns
    }
  }
}
