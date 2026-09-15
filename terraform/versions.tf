# Versoes fixadas. aws 5.x / eks 20.x / vpc 5.x / helm 2.x de proposito (decisao D11):
# as majors seguintes exigem aws 6 e mudam sintaxe; os outros repositorios estao em aws 5.
terraform {
  required_version = ">= 1.10" # use_lockfile no backend S3 (decisao D12)

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
  }
}
