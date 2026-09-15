# HTTP API (nao REST API) — design, secao 1. Este repositorio cria o API, o stage $default,
# o VPC Link, a integracao com o NLB e SO as rotas sem authorizer. A rota protegida
# ANY /api/v1/{proxy+} e as rotas /auth/* sao do oficina-lambda-auth (decisao D1 do Plano 2):
# duas route_key iguais em states diferentes dao ConflictException no apply.

resource "aws_apigatewayv2_api" "oficina" {
  name          = local.nome_api
  protocol_type = "HTTP"
  description   = "Borda unica da oficina: /auth/* (Lambda), /api/v1/* (VPC Link -> NLB -> EKS)."
}

resource "aws_cloudwatch_log_group" "apigw" {
  name              = "/aws/apigateway/${local.nome_api}"
  retention_in_days = var.log_retention_days
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.oficina.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigw.arn
    format = jsonencode({
      requestId        = "$context.requestId"
      ip               = "$context.identity.sourceIp"
      requestTime      = "$context.requestTime"
      routeKey         = "$context.routeKey"
      status           = "$context.status"
      responseLatency  = "$context.responseLatency"
      integrationError = "$context.integrationErrorMessage"
      authorizerError  = "$context.authorizer.error"
      correlationId    = "$context.requestId"
    })
  }

  # Teto global (todas as rotas).
  default_route_settings {
    throttling_rate_limit  = var.api_default_throttling_rate_limit
    throttling_burst_limit = var.api_default_throttling_burst_limit
  }

  # Throttling grosso de /auth/* — REQUISITO do oficina-lambda-auth (10 rps / burst 20).
  # Atras de flag (decisao D1): route_settings so aceita rotas que EXISTEM, e POST /auth/*
  # nasce no repo 4, que roda depois deste. Ligar via THROTTLING_AUTH_HABILITADO=true no
  # GitHub + re-executar o CD apos o primeiro apply do lambda-auth.
  dynamic "route_settings" {
    for_each = var.throttling_auth_habilitado ? toset(["POST /auth/cliente", "POST /auth/admin"]) : toset([])

    content {
      route_key              = route_settings.value
      throttling_rate_limit  = var.throttling_auth_rate_limit
      throttling_burst_limit = var.throttling_auth_burst_limit
    }
  }
}

resource "aws_apigatewayv2_vpc_link" "eks" {
  name               = "${var.project}-vpclink"
  security_group_ids = [aws_security_group.vpclink.id]
  subnet_ids         = module.vpc.private_subnets
}

# Integracao com o listener de PRODUCAO do NLB, usada pela rota PROTEGIDA que o
# oficina-lambda-auth cria (le o id em /oficina/apigw/vpc_link_integration_id). Mapeia o
# contexto do authorizer em headers informativos — a API revalida o JWT por conta propria
# (defesa em profundidade).
resource "aws_apigatewayv2_integration" "vpc_link" {
  api_id                 = aws_apigatewayv2_api.oficina.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  integration_uri        = aws_lb_listener.api["prd"].arn
  connection_type        = "VPC_LINK"
  connection_id          = aws_apigatewayv2_vpc_link.eks.id
  payload_format_version = "1.0"
  timeout_milliseconds   = 29000

  request_parameters = {
    "append:header.X-Perfil"    = "$context.authorizer.perfil"
    "append:header.X-Sub"       = "$context.authorizer.sub"
    "append:header.X-Documento" = "$context.authorizer.documento"
  }
}

# Integracao das rotas PUBLICAS (sem authorizer): mesmo listener, sem o mapeamento de
# $context.authorizer.* — nessas rotas o contexto nao existe e um mapeamento nao resolvido
# poderia virar 500 em GET /health, justamente o sinal do alerta de uptime.
resource "aws_apigatewayv2_integration" "vpc_link_publica" {
  api_id                 = aws_apigatewayv2_api.oficina.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  integration_uri        = aws_lb_listener.api["prd"].arn
  connection_type        = "VPC_LINK"
  connection_id          = aws_apigatewayv2_vpc_link.eks.id
  payload_format_version = "1.0"
  timeout_milliseconds   = 29000
}

# Rotas SEM authorizer (as mais especificas vencem ANY /api/v1/{proxy+} do lambda-auth —
# comportamento nativo do HTTP API). NAO acrescentar rotas /auth/* nem {proxy+} aqui.
locals {
  rotas_publicas = {
    health        = "GET /health"
    swagger       = "GET /swagger" # decisao D5: {proxy+} nao casa com /swagger sem sufixo
    swagger_proxy = "GET /swagger/{proxy+}"
    # Webhook de aprovacao do orcamento: segue protegido por X-Webhook-Token na API.
    aprovacao = "POST /api/v1/ordens-servico/{id}/orcamento/aprovacao"
  }
}

resource "aws_apigatewayv2_route" "publica" {
  for_each = local.rotas_publicas

  api_id    = aws_apigatewayv2_api.oficina.id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.vpc_link_publica.id}"
}
