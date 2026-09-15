# Sem credenciais no codigo: ambiente local (aws configure) ou OIDC no CI.
provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}
