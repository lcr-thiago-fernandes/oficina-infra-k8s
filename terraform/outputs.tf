output "cluster_name" {
  value = module.eks.cluster_name
}

output "configure_kubectl" {
  description = "Gera o kubeconfig local (a identidade precisa estar nas access entries)."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "ecr_repository_url" {
  value = aws_ecr_repository.api.repository_url
}

output "api_id" {
  value = aws_apigatewayv2_api.oficina.id
}

output "api_endpoint" {
  description = "URL base publica: GET /health, GET /swagger; /auth/* e /api/v1/* apos os Planos 4 e app."
  value       = aws_apigatewayv2_api.oficina.api_endpoint
}

output "vpc_link_id" {
  value = aws_apigatewayv2_vpc_link.eks.id
}

output "vpc_link_integration_id" {
  value = aws_apigatewayv2_integration.vpc_link.id
}

output "nlb_dns_name" {
  description = "NLB interno (so dentro da VPC). :80 = prd (30080), :81 = hml (30081)."
  value       = aws_lb.interno.dns_name
}

output "gha_deploy_role_arn" {
  description = "-> secret AWS_DEPLOY_ROLE_ARN no oficina-app."
  value       = aws_iam_role.gha_deploy.arn
}

output "gha_lambda_role_arn" {
  description = "-> secret AWS_LAMBDA_ROLE_ARN no oficina-lambda-auth."
  value       = aws_iam_role.gha_lambda.arn
}

output "eks_node_security_group_id" {
  value = module.eks.node_security_group_id
}
