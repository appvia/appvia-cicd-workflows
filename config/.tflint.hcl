plugin "aws" {
  enabled = true
  version = "0.49.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# Must match the required-tags rule and exclude_resource_types in config/tagging-policy.yaml
rule "aws_resource_missing_tags" {
  enabled = true
  tags    = ["Environment", "Product", "GitRepo"]
  exclude = []
}

rule "terraform_required_providers" {
  enabled = false
}

rule "terraform_module_pinned_source" {
  enabled = false
}

rule "terraform_unused_required_providers" {
  enabled = false
}

rule "terraform_standard_module_structure" {
  enabled = false
}

