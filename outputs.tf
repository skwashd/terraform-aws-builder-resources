locals {
  repo_url_prefix = {
    github = "https://github.com"
    gitlab = "https://gitlab.com"
  }
}

output "account_roles" {
  description = "A map of account IDs to the associated role ARNs and repo details"
  value = {
    for account_id, config in var.account_repo_map : account_id => merge(
      {
        planner  = aws_iam_role.planner[account_id].arn
        deployer = aws_iam_role.deployer[account_id].arn
        platform = var.platform
        branch   = config.branch != null ? config.branch : ""
        env      = config.env != null ? config.env : ""
      },
      contains(keys(local.repo_url_prefix), var.platform) ? {
        repo = "${local.repo_url_prefix[var.platform]}/${var.namespace}/${config.repo}"
      } : {}
    )
  }
}

output "state_bucket" {
  description = "The name of the S3 bucket used for Terraform state storage"
  value       = aws_s3_bucket.state.bucket
}
