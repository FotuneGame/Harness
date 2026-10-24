terraform {
  required_version = ">= 1.9.0"

  # State — рядом с данными кластера в volumes/ (в Git не попадает).
  backend "local" {
    path = "../volumes/terraform/terraform.tfstate"
  }
}
