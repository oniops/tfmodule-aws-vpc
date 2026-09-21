# Version constraints. The lower bound of required_version is a requirement (REQUIREMENTS 8.3):
# validation blocks may only reference their own variable below Terraform 1.9, so every
# check that spans two inputs is a precondition (ARCHITECTURE 9.2).
terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}
