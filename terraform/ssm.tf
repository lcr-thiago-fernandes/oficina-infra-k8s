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
  description = "Id da integracao HTTP_PROXY via VPC Link COM o mapeamento de contexto (X-Perfil/X-Sub/X-Documento), alvo da rota protegida criada pelo lambda-auth."
  type        = "String"
  value       = aws_apigatewayv2_integration.vpc_link.id
}

# ---------- Fase 4 (design fase4, secoes 3 e 6.4) ----------
# Lidos pelo terraform/ de oficina-app (IRSA do OS Service), oficina-billing-service e
# oficina-execucao-service (IRSA, target group + listener no NLB compartilhado, regras de SG).

resource "aws_ssm_parameter" "eks_oidc_provider_arn" {
  name        = "/${var.project}/eks/oidc_provider_arn"
  description = "ARN do OIDC provider do EKS (principal Federated da trust IRSA dos servicos)."
  type        = "String"
  value       = module.eks.oidc_provider_arn
}

resource "aws_ssm_parameter" "eks_oidc_provider_url" {
  name        = "/${var.project}/eks/oidc_provider_url"
  description = "Issuer OIDC do EKS SEM https:// (prefixo das chaves :sub/:aud da trust IRSA)."
  type        = "String"
  value       = module.eks.oidc_provider # o output do modulo ja remove o https://
}

resource "aws_ssm_parameter" "nlb_arn" {
  name        = "/${var.project}/nlb/arn"
  description = "ARN do NLB interno compartilhado (cada servico cria o proprio listener/target group)."
  type        = "String"
  value       = aws_lb.interno.arn
}

resource "aws_ssm_parameter" "nlb_security_group_id" {
  name        = "/${var.project}/nlb/security_group_id"
  description = "Id do SG do NLB interno (regras de entrada/saida das portas de cada servico)."
  type        = "String"
  value       = aws_security_group.nlb.id
}

resource "aws_ssm_parameter" "apigw_vpc_link_security_group_id" {
  name        = "/${var.project}/apigw/vpc_link_security_group_id"
  description = "Id do SG das ENIs do VPC Link (egress para o listener prd de cada servico)."
  type        = "String"
  value       = aws_security_group.vpclink.id
}

resource "aws_ssm_parameter" "eks_node_asg_names" {
  name        = "/${var.project}/eks/node_asg_names"
  description = "Nomes dos ASGs dos node groups gerenciados, separados por virgula (aws_autoscaling_attachment)."
  type        = "StringList"
  value       = join(",", module.eks.eks_managed_node_groups_autoscaling_group_names)
}
