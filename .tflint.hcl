config {
  format = "compact"
  plugin_dir = "~/.tflint.d/plugins"
  call_module_type = "all"
  force = false
  disabled_by_default = false
}

plugin "terraform" {
  enabled = true
  version = "0.15.0"
  source  = "github.com/terraform-linters/tflint-ruleset-terraform"
  preset  = "all"
}

rule "terraform_naming_convention" {
  enabled = true
  variable {
    custom = "^[A-Z][A-Z0-9]*(_[A-Z][A-Z0-9]*)*$"
  }
}

plugin "aws" {
  enabled = true
  version = "0.47.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
