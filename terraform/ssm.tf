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

resource "aws_ssm_parameter" "ecr_repository_url" {
  name        = "/${var.project}/ecr/repository_url"
  description = "URL completa do repositorio ECR (lida pelo CD do oficina-app: ECR_REPOSITORY)."
  type        = "String"
  value       = aws_ecr_repository.api.repository_url
}

resource "aws_ssm_parameter" "eks_cluster_name" {
  name        = "/${var.project}/eks/cluster_name"
  description = "Nome do cluster EKS (lido pelo CD do oficina-app: aws eks update-kubeconfig)."
  type        = "String"
  value       = module.eks.cluster_name
}

resource "aws_ssm_parameter" "eks_node_sg_id" {
  name        = "/${var.project}/network/eks_node_sg_id"
  description = "SG dos nos do EKS (o infra-db libera 5432 a partir dele)."
  type        = "String"
  value       = module.eks.node_security_group_id
}

resource "aws_ssm_parameter" "apigw_api_id" {
  name        = "/${var.project}/apigw/api_id"
  description = "Id do HTTP API (o lambda-auth pendura /auth/*, o authorizer e ANY /api/v1/{proxy+} nele)."
  type        = "String"
  value       = aws_apigatewayv2_api.oficina.id
}

resource "aws_ssm_parameter" "apigw_vpc_link_id" {
  name        = "/${var.project}/apigw/vpc_link_id"
  description = "Id do VPC Link para o NLB interno (informativo)."
  type        = "String"
  value       = aws_apigatewayv2_vpc_link.eks.id
}

resource "aws_ssm_parameter" "apigw_vpc_link_integration_id" {
  name        = "/${var.project}/apigw/vpc_link_integration_id"
  description = "Id da integracao HTTP_PROXY via VPC Link (alvo da rota protegida criada pelo lambda-auth)."
  type        = "String"
  value       = aws_apigatewayv2_integration.vpc_link.id
}
