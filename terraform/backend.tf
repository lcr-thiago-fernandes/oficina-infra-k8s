# Bucket e tabela criados por scripts/bootstrap.sh (uma vez, antes do primeiro init).
# Cada repositorio tem a propria key: nenhum le o state do outro (RFC-004).
# use_lockfile (lock nativo no S3, Terraform >= 1.10) + dynamodb_table (transicao; os
# outros repositorios ainda usam a tabela) — decisao D12.
terraform {
  backend "s3" {
    bucket         = "oficina-tfstate-fiap-15soat"
    key            = "infra-k8s/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "oficina-tfstate-lock"
    use_lockfile   = true
    encrypt        = true
  }
}
