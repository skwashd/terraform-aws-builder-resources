resource "aws_kms_key" "s3_state" {
  description             = "Terraform state bucket encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = data.aws_iam_policy_document.kms_s3_state.json

  tags = var.tags
}

resource "aws_kms_alias" "s3_state" {
  name          = "alias/s3-tfstate"
  target_key_id = aws_kms_key.s3_state.key_id
}
