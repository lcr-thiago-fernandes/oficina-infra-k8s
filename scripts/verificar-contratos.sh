#!/usr/bin/env bash
# Verifica, por grep no Terraform, os contratos deste repositorio com os outros tres
# (docs/contratos.md). E o analogo do job paridade-documento do oficina-lambda-auth:
# um `terraform validate` verde NAO pega uma rota a mais ou um nome de SSM a menos.
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1
TF_DIR="terraform"
falhas=0

erro() { echo "ERRO: $*" >&2; falhas=$((falhas + 1)); }
ok()   { echo "OK:   $*"; }

# 1. Rotas PROIBIDAS (pertencem ao oficina-lambda-auth).
# 1a. A rota protegida, entre aspas, nao pode aparecer em NENHUM .tf (nem como valor de mapa).
if grep -rn --include='*.tf' -F '"ANY /api/v1/{proxy+}"' "$TF_DIR" >/dev/null; then
  erro "rota 'ANY /api/v1/{proxy+}' declarada aqui; ela pertence ao oficina-lambda-auth (ConflictException no apply)."
else
  ok "rota 'ANY /api/v1/{proxy+}' nao e criada aqui."
fi
# 1b. /auth/* so pode aparecer em route_settings do stage, nunca no mapa de rotas publicas.
if awk '/rotas_publicas = \{/,/^  \}/' "$TF_DIR/apigw.tf" | grep '/auth/' >/dev/null; then
  erro "rota /auth/* dentro de local.rotas_publicas; /auth/* pertence ao oficina-lambda-auth."
else
  ok "nenhuma rota /auth/* em local.rotas_publicas."
fi
# 1c. Nenhum aws_apigatewayv2_route com route_key literal de /auth/* ou {proxy+} da API.
if grep -rn --include='*.tf' -E 'route_key[[:space:]]*=[[:space:]]*"(POST /auth/|ANY /api/v1/)' "$TF_DIR" >/dev/null; then
  erro "route_key literal de /auth/* ou ANY /api/v1/* declarada aqui."
else
  ok "nenhuma route_key literal do oficina-lambda-auth."
fi

# 2. Rotas OBRIGATORIAS sem authorizer (valores do map local.rotas_publicas).
for rota in 'GET /health' 'GET /swagger/{proxy+}'; do
  if grep -rn --include='*.tf' -F "\"$rota\"" "$TF_DIR" >/dev/null; then
    ok "rota '$rota' presente."
  else
    erro "rota obrigatoria '$rota' ausente."
  fi
done
# 2b. Fase 4: o webhook de aprovacao saiu do OS Service (agora POST /billing/webhooks/mercadopago,
# criado pelo oficina-billing-service). Nenhuma rota /billing/* ou /execucao/* nasce aqui.
if grep -rn --include='*.tf' -E '"POST /api/v1/ordens-servico/\{id\}/orcamento/aprovacao"|"[A-Z]+ /(billing|execucao)/' "$TF_DIR" >/dev/null; then
  erro "rota do webhook da Fase 3 ou rota /billing|/execucao declarada aqui (pertencem aos servicos da Fase 4)."
else
  ok "nenhuma rota do webhook da Fase 3 nem de /billing|/execucao."
fi

# 3. Parametros SSM publicados (nomes exatos lidos pelos outros repositorios).
for ssm in '/network/vpc_id' '/network/private_subnet_ids' '/network/eks_node_sg_id' \
           '/apigw/api_id' '/apigw/vpc_link_id' '/apigw/vpc_link_integration_id' \
           '/eks/cluster_name' '/ecr/repository_url' \
           '/eks/oidc_provider_arn' '/eks/oidc_provider_url' '/nlb/arn' '/nlb/security_group_id' \
           '/apigw/vpc_link_security_group_id' '/eks/node_asg_names'; do
  if grep -n -F "name        = \"/\${var.project}${ssm}\"" "$TF_DIR/ssm.tf" >/dev/null; then
    ok "SSM /oficina${ssm} publicado."
  else
    erro "SSM /oficina${ssm} nao encontrado em ${TF_DIR}/ssm.tf."
  fi
done
if grep -n -A3 'private_subnet_ids' "$TF_DIR/ssm.tf" | grep 'type        = "StringList"' >/dev/null; then
  ok "/oficina/network/private_subnet_ids e StringList."
else
  erro "/oficina/network/private_subnet_ids precisa ser StringList."
fi

if grep -n -A3 '"eks_node_asg_names"' "$TF_DIR/ssm.tf" | grep 'type        = "StringList"' >/dev/null; then
  ok "/oficina/eks/node_asg_names e StringList."
else
  erro "/oficina/eks/node_asg_names precisa ser StringList."
fi
# O issuer vai SEM https:// (output oidc_provider do modulo EKS, nao cluster_oidc_issuer_url).
if grep -n -A4 '"eks_oidc_provider_url"' "$TF_DIR/ssm.tf" | grep -E 'value[[:space:]]+= module\.eks\.oidc_provider([[:space:]]|$)' >/dev/null; then
  ok "/oficina/eks/oidc_provider_url = module.eks.oidc_provider (sem https://)."
else
  erro "/oficina/eks/oidc_provider_url precisa vir de module.eks.oidc_provider (sem https://)."
fi
# A role de deploy do oficina-app le /oficina/os-service/* (irsa_role_arn da Fase 4).
if grep -n -F "parameter/\${var.project}/os-service/*" "$TF_DIR/iam-oidc.tf" >/dev/null; then
  ok "oficina-gha-deploy le /oficina/os-service/*."
else
  erro "oficina-gha-deploy sem ssm:GetParameter em /oficina/os-service/*."
fi

# 4. Segredos em texto puro criados aqui.
for segredo in 'jwt_secret' 'newrelic_license_key'; do
  if grep -n -F "name                    = \"\${var.project}/${segredo}\"" "$TF_DIR/secrets.tf" >/dev/null; then
    ok "segredo oficina/${segredo} criado."
  else
    erro "segredo oficina/${segredo} ausente em ${TF_DIR}/secrets.tf."
  fi
done
if grep -rn --include='*.tf' -E 'secret_string[[:space:]]*=[[:space:]]*jsonencode' "$TF_DIR" >/dev/null; then
  erro "secret_string com jsonencode: os consumidores leem texto puro."
fi

# 5. NodePorts do contrato com o oficina-app.
if grep -n -A3 'variable "nodeport_prd"' "$TF_DIR/variables.tf" | grep 'default     = 30080' >/dev/null; then
  ok "nodeport_prd = 30080"
else
  erro "nodeport_prd != 30080"
fi
if grep -n -A3 'variable "nodeport_hml"' "$TF_DIR/variables.tf" | grep 'default     = 30081' >/dev/null; then
  ok "nodeport_hml = 30081"
else
  erro "nodeport_hml != 30081"
fi

# 6. Throttling de /auth/* (requisito do oficina-lambda-auth: 10 rps / burst 20).
if grep -n -F '"POST /auth/cliente", "POST /auth/admin"' "$TF_DIR/apigw.tf" >/dev/null; then
  ok "route_settings para POST /auth/*"
else
  erro "route_settings de POST /auth/* ausente."
fi
if grep -n -A3 'variable "throttling_auth_rate_limit"' "$TF_DIR/variables.tf" | grep 'default     = 10' >/dev/null; then
  ok "throttling_auth_rate_limit = 10"
else
  erro "throttling_auth_rate_limit != 10"
fi
if grep -n -A3 'variable "throttling_auth_burst_limit"' "$TF_DIR/variables.tf" | grep 'default     = 20' >/dev/null; then
  ok "throttling_auth_burst_limit = 20"
else
  erro "throttling_auth_burst_limit != 20"
fi

# 7. Roles OIDC com os nomes que os outros repositorios esperam.
for role in 'gha-infra' 'gha-deploy' 'gha-lambda'; do
  if grep -rn --include='*.tf' -F "\"\${var.project}-${role}\"" "$TF_DIR" >/dev/null; then
    ok "role oficina-${role}"
  else
    erro "role oficina-${role} nao referenciada."
  fi
done

# 8. REPOS_INFRA do bootstrap: quem assume oficina-gha-infra (Fase 4: os tres servicos aplicam o proprio terraform/).
for repo in oficina-infra-k8s oficina-infra-db oficina-app oficina-billing-service oficina-execucao-service; do
  if grep -E '^REPOS_INFRA=\(' scripts/bootstrap.sh | grep -F "\"$repo\"" >/dev/null; then
    ok "REPOS_INFRA inclui $repo"
  else
    erro "REPOS_INFRA (scripts/bootstrap.sh) sem $repo"
  fi
done

echo
if [ "$falhas" -gt 0 ]; then
  echo "${falhas} contrato(s) violado(s)." >&2
  exit 1
fi
echo "Todos os contratos verificados."
