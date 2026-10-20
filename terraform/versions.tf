terraform {
  required_version = ">= 1.9.0"

  # State хранится локально (terraform/terraform.tfstate, исключён из Git).
  backend "local" {
    path = "terraform.tfstate"
  }
}
