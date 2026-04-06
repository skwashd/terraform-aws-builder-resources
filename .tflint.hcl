tflint {
  required_version = ">= 0.61.0"
}

plugin "aws" {
  enabled = true
  version = "0.46.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}