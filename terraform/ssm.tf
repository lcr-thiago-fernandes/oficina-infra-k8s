# Contrato entre repositorios (RFC-004): identificadores no SSM, nunca terraform_remote_state.
# Nomes EXATOS lidos por oficina-infra-db, oficina-lambda-auth e oficina-app.

resource "aws_ssm_parameter" "vpc_id" {
  name        = "/${var.project}/network/vpc_id"
  description = "VPC da oficina (lido por infra-db e lambda-auth)."
  type        = "String"
  value       = module.vpc.vpc_id
}

resource "aws_ssm_parameter" "private_subnet_ids" {
  name        = "/${var.project}/network/private_subnet_ids"
  description = "Subnets privadas, separadas por virgula (vpc_config da oficina-auth-api; subnet group do RDS)."
  type        = "StringList"
  value       = join(",", module.vpc.private_subnets)
}
