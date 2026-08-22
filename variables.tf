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
    repo_id            = optional(string, "*")
    branch             = optional(string)
    env                = optional(string)
    deployer_role_arns = optional(list(string), [])
    planner_role_arns  = optional(list(string), [])
  }))

  validation {
    condition = var.platform == "none" || alltrue([
      for k, v in var.account_repo_map : v.repo != null
    ])
    error_message = "Each entry must set repo when platform is not none."
  }

  validation {
    condition = var.platform != "gitlab" || alltrue([
      for k, v in var.account_repo_map : v.branch != null
    ])
    error_message = "Each entry must set branch when platform is gitlab."
  }

  validation {
    condition = var.platform == "none" || alltrue([
      for k, v in var.account_repo_map : v.branch != null || v.env != null
    ])
    error_message = "Each entry must set at least one of branch or env."
  }

  validation {
    condition = alltrue([
      for k, v in var.account_repo_map : v.repo_id == "*" || can(regex("^[1-9][0-9]*$", v.repo_id))
    ])
    error_message = "Each repo_id must be the numeric GitHub repository ID, with no leading zero, or \"*\"."
  }

  validation {
    condition = var.platform == "github" || alltrue([
      for k, v in var.account_repo_map : v.repo_id == "*"
    ])
    error_message = "repo_id is only supported when platform is github."
  }

  validation {
    condition = var.platform != "github" || !var.immutable_subs_only || alltrue([
      for k, v in var.account_repo_map : v.repo_id != "*"
    ])
    error_message = "Each repo_id must be set to the numeric GitHub repository ID when immutable_subs_only is true."
  }
}

variable "namespace_id" {
  type        = string
  description = "Numeric GitHub organisation or user ID. Used in the immutable OIDC subject claim and as the repository_owner_id trust condition. Defaults to \"*\", which matches any owner ID and omits the repository_owner_id condition. GitHub only."
  default     = "*"

  validation {
    condition     = var.namespace_id == "*" || can(regex("^[1-9][0-9]*$", var.namespace_id))
    error_message = "namespace_id must be the numeric GitHub owner ID, with no leading zero, or \"*\"."
  }

  validation {
    condition     = var.namespace_id == "*" || var.platform == "github"
    error_message = "namespace_id is only supported when platform is github."
  }

  validation {
    condition     = !var.immutable_subs_only || var.namespace_id != "*"
    error_message = "namespace_id must be set to the numeric GitHub owner ID when immutable_subs_only is true."
  }
}

variable "immutable_subs_only" {
  type        = bool
  description = "Only trust GitHub's immutable OIDC subject claim format. Leave false while any repository in account_repo_map may still emit the legacy format; the trust policy then accepts both. GitHub only."
  default     = false

  validation {
    condition     = !var.immutable_subs_only || var.platform == "github"
    error_message = "immutable_subs_only is only supported when platform is github."
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

variable "override_provider_config" {
  type = object({
    oidc_provider_url = optional(string)
    oidc_audience     = optional(string)
    oidc_thumbprints  = optional(list(string))
  })

  description = "Override OIDC provider configuration. Needed for BitBucket audience and for custom OIDC providers."
  default     = {}
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
}

locals {
  account_ids = toset(keys(var.account_repo_map))

  oidc_provider_url = var.platform != "none" ? var.override_provider_config.oidc_provider_url != null ? var.override_provider_config.oidc_provider_url : {
    github    = "https://token.actions.githubusercontent.com"
    gitlab    = "https://gitlab.com"
    bitbucket = "https://api.bitbucket.org/2.0/workspaces/${var.namespace}/pipelines-config/identity/oidc"
  }[var.platform] : null

  oidc_audience = var.platform != "none" ? var.override_provider_config.oidc_audience != null ? var.override_provider_config.oidc_audience : {
    github    = "sts.amazonaws.com"
    gitlab    = "sts.amazonaws.com"
    bitbucket = "ari:cloud:bitbucket::workspace/${var.namespace}"
  }[var.platform] : null

  oidc_thumbprints = var.platform != "none" ? var.override_provider_config.oidc_thumbprints != null ? var.override_provider_config.oidc_thumbprints : {
    github    = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]
    gitlab    = []
    bitbucket = ["a031c46782e6e6c662c2c87c76da9aa62ccabd8e"]
  }[var.platform] : []

  oidc_provider_host = local.oidc_provider_url != null ? replace(local.oidc_provider_url, "https://", "") : null
}
