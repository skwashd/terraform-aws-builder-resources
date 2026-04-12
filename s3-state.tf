resource "aws_s3_bucket" "state" {
  bucket = "tfstate-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}-an"

  bucket_namespace = "account-regional"

  force_destroy = false

  tags = var.tags
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_logging" "state" {
  count = var.logging_bucket != null ? 1 : 0

  bucket        = aws_s3_bucket.state.id
  target_bucket = var.logging_bucket
  target_prefix = "/s3/${aws_s3_bucket.state.id}/"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3_state.arn
    }

    blocked_encryption_types = [
      "NONE"
    ]
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "kms_s3_state" {
  statement {
    sid       = "EnableIAM"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid = "AllowBuilders"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [for acct in local.account_ids : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/TerraformDeployer-${acct}"]
    }
  }

  statement {
    sid = "AllowPlanners"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
    ]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [for acct in local.account_ids : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/TerraformPlanner-${acct}"]
    }
  }
}

data "aws_iam_policy_document" "s3_state" {
  statement {
    sid     = "EnableIAM"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*"
    ]
    principals {
      type        = "AWS"
      identifiers = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "TfListBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    resources = [aws_s3_bucket.state.arn]

    principals {
      type        = "AWS"
      identifiers = [for acct in local.account_ids : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/TerraformDeployer-${acct}"]
    }
  }

  dynamic "statement" {
    for_each = local.account_ids

    content {
      actions = [
        "s3:GetObject",
        "s3:PutObject",
      ]
      resources = [
        "${aws_s3_bucket.state.arn}/acct-${statement.value}/state",
      ]
      principals {
        type = "AWS"
        identifiers = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/TerraformDeployer-${statement.value}"
        ]
      }
    }
  }

  dynamic "statement" {
    for_each = local.account_ids

    content {
      actions = [
        "s3:GetObject",
      ]
      resources = [
        "${aws_s3_bucket.state.arn}/acct-${statement.value}/state",
      ]
      principals {
        type = "AWS"
        identifiers = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/TerraformPlanner-${statement.value}"
        ]
      }
    }
  }

  statement {
    sid     = "AllowSSLRequestsOnly"
    actions = ["s3:*"]
    effect  = "Deny"
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*"
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}

resource "aws_s3_bucket_policy" "s3_state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.s3_state.json

  depends_on = [aws_s3_bucket_public_access_block.state]
}
