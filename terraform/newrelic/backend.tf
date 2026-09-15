# State proprio (decisao D9): este root so e aplicado quando a conta New Relic existir.
terraform {
  backend "s3" {
    bucket         = "oficina-tfstate-fiap-15soat"
    key            = "infra-k8s-newrelic/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "oficina-tfstate-lock"
    use_lockfile   = true
    encrypt        = true
  }
}
