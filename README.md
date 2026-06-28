# AWS Terraform Builder Account Resources

A Terraform module that sets up the AWS infrastructure needed for CI/CD pipelines to manage Terraform state in a common account. It creates:

- An OIDC identity provider for your CI/CD platform
- IAM deployer and planner roles (one pair per entry in `account_repo_map`)
- A KMS-encrypted S3 bucket for storing Terraform state, usable as a backend for AWS and non-AWS providers alike
- Bucket and key policies scoped to the created roles

Supports GitHub Actions, GitLab CI/CD, and Bitbucket Pipelines.

## How it works

The module runs in a central "builder" AWS account. For each entry in `account_repo_map`, it creates two IAM roles:

- **Deployer** (`TerraformDeployer-{key}`) -- has read/write access to that entry's state file in S3. When the key is a 12-digit AWS account ID it can also assume `TerraformDeployer` in that target account. The OIDC trust policy restricts this role to a specific branch or environment.
- **Planner** (`TerraformPlanner-{key}`) -- has read-only access to the state file. When the key is a 12-digit AWS account ID it can also assume `TerraformPlanner` in that target account. The OIDC trust policy allows any ref from the repository (so plan runs work on PRs).

When the map key is a 12-digit AWS account ID the roles get the standard cross-account assume-role permission. When the key is any other string (e.g. `cloudflare`) the cross-account assume-role statement is omitted -- the roles only get read/write (deployer) or read (planner) access to the state object in S3, making it straightforward to manage state for non-AWS providers using the same bucket.

Your CI/CD pipeline authenticates via OIDC (no long-lived credentials), assumes the appropriate builder role, then assumes the target account role to run Terraform (or passes provider credentials directly for non-AWS providers).

## Usage

### GitHub Actions

GitHub supports filtering deployer access by either environment or branch. Set exactly one of `env` or `branch` per entry.

```hcl
module "builder" {
  source = "git::https://github.com/your-org/terraform-aws-builder-resources.git?ref=v1.0.0"

  platform  = "github"
  namespace = "your-github-org"

  account_repo_map = {
    "111111111111" = {
      repo = "infra-production"
      env  = "production"
    }
    "222222222222" = {
      repo   = "infra-staging"
      branch = "main"
    }
  }

  tags = {
    ManagedBy = "terraform"
  }
}
```

When `env` is set, the deployer trust policy matches `repo:your-github-org/infra-production:environment:production`. When `branch` is set, it matches `repo:your-github-org/infra-staging:ref:refs/heads/main`.

### GitLab CI/CD

GitLab uses branch-based filtering only. Every entry must set `branch`.

```hcl
module "builder" {
  source = "git::https://github.com/your-org/terraform-aws-builder-resources.git?ref=v1.0.0"

  platform  = "gitlab"
  namespace = "your-gitlab-group"

  account_repo_map = {
    "111111111111" = {
      repo   = "infra-production"
      branch = "main"
    }
  }

  tags = {
    ManagedBy = "terraform"
  }
}
```

The deployer trust policy matches `project_path:your-gitlab-group/infra-production:ref_type:branch:ref:main`.

### Bitbucket Pipelines

Bitbucket uses repository UUIDs (not names) and a separate `branchName` OIDC claim. Every entry must set `branch`, and `repo` should be the repository UUID. The `namespace` should be your workspace UUID.

```hcl
module "builder" {
  source = "git::https://github.com/your-org/terraform-aws-builder-resources.git?ref=v1.0.0"

  platform  = "bitbucket"
  namespace = "{workspace-uuid}"

  account_repo_map = {
    "111111111111" = {
      repo   = "{repo-uuid}"
      branch = "main"
    }
  }

  tags = {
    ManagedBy = "terraform"
  }
}
```

The deployer trust policy matches the repository UUID in the `sub` claim and the branch in the `branchName` claim.

### Non-AWS backends

You can use the same state bucket as a Terraform backend for non-AWS providers (such as Cloudflare, Fastly, or Datadog) by using a descriptive string as the map key instead of an AWS account ID.

```hcl
module "builder" {
  source = "git::https://github.com/your-org/terraform-aws-builder-resources.git?ref=v1.0.0"

  platform  = "github"
  namespace = "your-github-org"

  account_repo_map = {
    "111111111111" = {
      repo   = "infra-aws-production"
      branch = "main"
    }
    "cloudflare" = {
      repo   = "infra-cloudflare"
      branch = "main"
    }
  }

  tags = {
    ManagedBy = "terraform"
  }
}
```

For the `cloudflare` entry this creates `TerraformDeployer-cloudflare` and `TerraformPlanner-cloudflare` IAM roles with S3 and KMS access to the state object but **no** `sts:AssumeRole` permission for a target AWS account.

Configure the Terraform backend in the non-AWS repo using the `state_bucket` module output:

```hcl
terraform {
  backend "s3" {
    bucket               = "<state_bucket output>"
    key                  = "acct-cloudflare/state"
    dynamodb_table       = ""          # state locking uses the .tflock object, not DynamoDB
    region               = "us-east-1" # region where the builder account is deployed
    encrypt              = true
  }
}
```

The state lock object is stored alongside the state at `acct-cloudflare/state.tflock`. Provider credentials (e.g. a Cloudflare API token) are supplied to the pipeline separately -- this module only manages state-bucket access.

## Additional role ARNs

Each deployer/planner role automatically gets permission to assume `TerraformDeployer` or `TerraformPlanner` in its target account. If your pipeline also needs to assume roles in other accounts (for example, reading SSM parameters from a shared services account), you can add those ARNs at two levels:

Per-account, via `account_repo_map`:

```hcl
account_repo_map = {
  "111111111111" = {
    repo   = "infra-production"
    branch = "main"
    deployer_role_arns = ["arn:aws:iam::999999999999:role/read-shared-config"]
  }
}
```

Globally, via `additional_deployer_role_arns` / `additional_planner_role_arns` (applied to all deployer/planner roles):

```hcl
additional_deployer_role_arns = [
  "arn:aws:iam::999999999999:role/read-shared-config",
]
```

## S3 access logging

Pass `logging_bucket` with the name of an existing S3 bucket to enable access logging on the state bucket. If omitted, logging is disabled.

```hcl
module "builder" {
  # ...
  logging_bucket = "my-s3-access-logs-bucket"
}
```

## Outputs

The `account_roles` output is a map keyed by the `account_repo_map` key (an AWS account ID, or the descriptive string used for a non-AWS backend). Each value contains:

| Key | Description |
|-----|-------------|
| `deployer` | ARN of the deployer role for this account |
| `planner` | ARN of the planner role for this account |
| `platform` | The platform value passed to the module |
| `branch` | Branch filter (if set) |
| `env` | Environment filter (if set, GitHub only) |
| `repo` | Full repository URL (GitHub and GitLab only) |

## Target account roles

Each target AWS account needs `TerraformDeployer` and `TerraformPlanner` IAM roles that trust the builder account. This module does not create those roles -- they live in the target accounts.

A CloudFormation template is provided at [`resources/terraform-roles.yaml`](resources/terraform-roles.yaml). It creates both roles with appropriate trust policies and permissions:

- `TerraformDeployer` -- `AdministratorAccess`
- `TerraformPlanner` -- `ReadOnlyAccess`, plus scoped KMS decrypt and Secrets Manager read access via a supplementary policy

The template takes three parameters:

| Parameter | Description |
|-----------|-------------|
| `BuilderAccountId` | Account ID where this Terraform module is deployed (the builder account) |
| `ResourcePrefix` | Prefix used for KMS alias and Secrets Manager scoping in the planner policy |
| `SessionId` | Expected session name for the `sts:AssumeRole` trust condition |

Deploy it as a [CloudFormation StackSet](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/what-is-cfnstacksets.html) with service-managed permissions to roll it out across your AWS Organization automatically. This way every new account gets the roles without manual intervention.

```bash
aws cloudformation create-stack-set \
  --stack-set-name terraform-roles \
  --template-body file://resources/terraform-roles.yaml \
  --parameters \
    ParameterKey=BuilderAccountId,ParameterValue=123456789012 \
    ParameterKey=ResourcePrefix,ParameterValue=myapp \
    ParameterKey=SessionId,ParameterValue=GitHubActions \
  --permission-model SERVICE_MANAGED \
  --auto-deployment Enabled=true,RetainStacksOnAccountRemoval=false \
  --capabilities CAPABILITY_NAMED_IAM
```

With `--auto-deployment Enabled=true`, accounts added to the Organization later will receive the stack automatically.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10.0, <2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.37.0, < 7.0.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.38.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_openid_connect_provider.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider) | resource |
| [aws_iam_policy.deployer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.planner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.deployer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.planner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.deployer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.planner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_kms_alias.s3_state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.s3_state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_s3_bucket.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_logging.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_logging) | resource |
| [aws_s3_bucket_ownership_controls.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.s3_state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.bitbucket_deployer_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.bitbucket_planner_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.deployer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.github_deployer_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.github_planner_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.gitlab_deployer_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.gitlab_planner_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.kms_s3_state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.none_deployer_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.none_planner_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.planner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.s3_state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_account_repo_map"></a> [account\_repo\_map](#input\_account\_repo\_map) | A map of account IDs to repository configuration | <pre>map(object({<br/>    repo               = optional(string)<br/>    branch             = optional(string)<br/>    env                = optional(string)<br/>    deployer_role_arns = optional(list(string), [])<br/>    planner_role_arns  = optional(list(string), [])<br/>  }))</pre> | n/a | yes |
| <a name="input_additional_deployer_role_arns"></a> [additional\_deployer\_role\_arns](#input\_additional\_deployer\_role\_arns) | Additional role ARNs all deployer roles can assume | `list(string)` | `[]` | no |
| <a name="input_additional_planner_role_arns"></a> [additional\_planner\_role\_arns](#input\_additional\_planner\_role\_arns) | Additional role ARNs all planner roles can assume | `list(string)` | `[]` | no |
| <a name="input_additional_trust_principal_arns"></a> [additional\_trust\_principal\_arns](#input\_additional\_trust\_principal\_arns) | IAM principal ARNs allowed to assume the deployer and planner roles (e.g. for testing before pipeline OIDC is configured) | `list(string)` | `[]` | no |
| <a name="input_logging_bucket"></a> [logging\_bucket](#input\_logging\_bucket) | Name of an existing S3 bucket for access logging. If not set, logging is disabled. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Platform namespace (GitHub org, GitLab group, Bitbucket workspace UUID) | `string` | `""` | no |
| <a name="input_override_provider_config"></a> [override\_provider\_config](#input\_override\_provider\_config) | Override OIDC provider configuration. Needed for BitBucket audience and for custom OIDC providers. | <pre>object({<br/>    oidc_provider_url = optional(string)<br/>    oidc_audience     = optional(string)<br/>    oidc_thumbprints  = optional(list(string))<br/>  })</pre> | `{}` | no |
| <a name="input_platform"></a> [platform](#input\_platform) | CI/CD platform: github, gitlab, bitbucket, or none | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_account_roles"></a> [account\_roles](#output\_account\_roles) | A map of account IDs to the associated role ARNs and repo details |
| <a name="output_state_bucket"></a> [state\_bucket](#output\_state\_bucket) | The name of the S3 bucket used for Terraform state storage |
<!-- END_TF_DOCS -->