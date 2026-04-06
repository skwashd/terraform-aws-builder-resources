locals {
  deployer_assume_role_docs = merge(
    { for k, v in data.aws_iam_policy_document.github_deployer_assume_role : k => v.json },
    { for k, v in data.aws_iam_policy_document.gitlab_deployer_assume_role : k => v.json },
    { for k, v in data.aws_iam_policy_document.bitbucket_deployer_assume_role : k => v.json },
    { for k, v in data.aws_iam_policy_document.none_deployer_assume_role : k => v.json },
  )
  planner_assume_role_docs = merge(
    { for k, v in data.aws_iam_policy_document.github_planner_assume_role : k => v.json },
    { for k, v in data.aws_iam_policy_document.gitlab_planner_assume_role : k => v.json },
    { for k, v in data.aws_iam_policy_document.bitbucket_planner_assume_role : k => v.json },
    { for k, v in data.aws_iam_policy_document.none_planner_assume_role : k => v.json },
  )
}

resource "aws_iam_openid_connect_provider" "this" {
  count = var.platform != "none" ? 1 : 0

  url             = local.oidc_provider_url
  client_id_list  = [local.oidc_audience]
  thumbprint_list = local.oidc_thumbprints
}

moved {
  from = aws_iam_openid_connect_provider.this
  to   = aws_iam_openid_connect_provider.this[0]
}

# Deployer

data "aws_iam_policy_document" "deployer" {
  for_each = var.account_repo_map

  statement {
    actions = [
      "sts:AssumeRole",
    ]

    resources = concat(
      ["arn:aws:iam::${each.key}:role/TerraformDeployer"],
      each.value.deployer_role_arns,
      var.additional_deployer_role_arns,
    )
  }

  statement {
    actions = [
      "s3:ListBucket",
    ]

    resources = [
      aws_s3_bucket.state.arn,
    ]
  }

  statement {
    actions = [
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:PutObject",
    ]

    resources = [
      "${aws_s3_bucket.state.arn}/acct-${each.key}/state",
      "${aws_s3_bucket.state.arn}/acct-${each.key}/state.tflock"
    ]
  }

  statement {
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:ReEncrypt*",
    ]

    resources = [
      aws_kms_key.s3_state.arn
    ]
  }
}

resource "aws_iam_policy" "deployer" {
  for_each = local.account_ids

  name        = "TerraformDeployer-${each.value}"
  description = "Allows the TerraformDeployer role to access required resources"
  policy      = data.aws_iam_policy_document.deployer[each.value].json

  tags = var.tags
}

resource "aws_iam_role" "deployer" {
  for_each = local.account_ids

  name                 = "TerraformDeployer-${each.value}"
  assume_role_policy   = local.deployer_assume_role_docs[each.value]
  max_session_duration = 7200

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "deployer" {
  for_each = local.account_ids

  role       = aws_iam_role.deployer[each.value].name
  policy_arn = aws_iam_policy.deployer[each.value].arn
}

# Planner

data "aws_iam_policy_document" "planner" {
  for_each = var.account_repo_map

  statement {
    actions = [
      "sts:AssumeRole",
    ]

    resources = concat(
      ["arn:aws:iam::${each.key}:role/TerraformPlanner"],
      each.value.planner_role_arns,
      var.additional_planner_role_arns,
    )
  }

  statement {
    actions = [
      "s3:ListBucket",
    ]

    resources = [
      aws_s3_bucket.state.arn,
    ]
  }

  statement {
    actions = [
      "s3:GetObject"
    ]

    resources = [
      "${aws_s3_bucket.state.arn}/acct-${each.key}/state",
      "${aws_s3_bucket.state.arn}/acct-${each.key}/state.tflock"
    ]
  }

  statement {
    actions = [
      "s3:DeleteObject",
      "s3:PutObject",
    ]

    resources = [
      "${aws_s3_bucket.state.arn}/acct-${each.key}/state.tflock"
    ]
  }

  statement {
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:ReEncrypt*",
    ]

    resources = [
      aws_kms_key.s3_state.arn
    ]
  }
}

resource "aws_iam_policy" "planner" {
  for_each = local.account_ids

  name        = "TerraformPlanner-${each.value}"
  description = "Allows the TerraformPlanner role to access required resources"
  policy      = data.aws_iam_policy_document.planner[each.value].json

  tags = var.tags
}

resource "aws_iam_role" "planner" {
  for_each = local.account_ids

  name                 = "TerraformPlanner-${each.value}"
  assume_role_policy   = local.planner_assume_role_docs[each.value]
  max_session_duration = 3600

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "planner" {
  for_each = local.account_ids

  role       = aws_iam_role.planner[each.value].name
  policy_arn = aws_iam_policy.planner[each.value].arn
}
