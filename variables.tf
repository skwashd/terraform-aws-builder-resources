variable "platform" {
  type        = string
  description = "CI/CD platform: github, gitlab, bitbucket, or none"

  validation {
    condition     = contains(["github", "gitlab", "bitbucket", "none"], var.platform)
    error_message = "Platform must be github, gitlab, bitbucket, or none."
  }
}

variable "namespace" {
  type        = string
  description = "Platform namespace (GitHub org, GitLab group, Bitbucket workspace UUID)"
  default     = ""

  validation {
    condition     = var.platform == "none" || var.namespace != ""
    error_message = "namespace is required when platform is not none."
  }
}

variable "account_repo_map" {
  description = "A map of account IDs to repository configuration"

  type = map(object({
    repo               = optional(string)
    branch             = optional(string)
    env                = optional(string)
    deployer_role_arns = optional(list(string), [])
    planner_role_arns  = optional(list(string), [])
  }))

  validation {
    condition = alltrue([
      for k, v in var.account_repo_map : v.repo != null ? (v.branch != null || v.env != null) : true
    ])
    error_message = "Each entry must set at least one of branch or env when repo is set."
  }
}

variable "additional_deployer_role_arns" {
  type        = list(string)
  description = "Additional role ARNs all deployer roles can assume"
  default     = []
}

variable "additional_planner_role_arns" {
  type        = list(string)
  description = "Additional role ARNs all planner roles can assume"
  default     = []
}

variable "additional_trust_principal_arns" {
  type        = list(string)
  description = "IAM principal ARNs allowed to assume the deployer and planner roles (e.g. for testing before pipeline OIDC is configured)"
  default     = []

  validation {
    condition     = var.platform != "none" || length(var.additional_trust_principal_arns) > 0
    error_message = "additional_trust_principal_arns must be set when platform is none."
  }
}

variable "logging_bucket" {
  type        = string
  description = "Name of an existing S3 bucket for access logging. If not set, logging is disabled."
  default     = null
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
}

locals {
  account_ids = toset(keys(var.account_repo_map))

  oidc_provider_url = var.platform != "none" ? {
    github    = "https://token.actions.githubusercontent.com"
    gitlab    = "https://gitlab.com"
    bitbucket = "https://api.bitbucket.org/2.0/workspaces/${var.namespace}/pipelines-config/identity/oidc"
  }[var.platform] : null

  oidc_audience = var.platform != "none" ? {
    github    = "sts.amazonaws.com"
    gitlab    = "sts.amazonaws.com"
    bitbucket = "ari:cloud:bitbucket::workspace/${var.namespace}"
  }[var.platform] : null

  oidc_thumbprints = var.platform != "none" ? {
    github    = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]
    gitlab    = []
    bitbucket = ["a031c46782e6e6c662c2c87c76da9aa62ccabd8e"]
  }[var.platform] : []

  oidc_provider_host = local.oidc_provider_url != null ? replace(local.oidc_provider_url, "https://", "") : null
}
