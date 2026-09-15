# Contratos deste repositório com os demais

Complementa `oficina-app/docs/contratos-entre-repositorios.md` (seções 2, 3, 4, 6a) e
`oficina-lambda-auth/docs/contratos.md`. Cada item falha em silêncio se divergir; o job
`contratos` do CI (`scripts/verificar-contratos.sh`) confere os que dá para conferir por grep.

## O que este repositório PUBLICA (SSM Parameter Store)

| Parâmetro | Tipo | Valor | Quem lê |
|---|---|---|---|
| `/oficina/network/vpc_id` | String | id da VPC | infra-db, lambda-auth |
| `/oficina/network/private_subnet_ids` | **StringList** | subnets privadas, separadas por vírgula | infra-db, lambda-auth |
| `/oficina/network/eks_node_sg_id` | String | SG dos nós do EKS | infra-db (libera 5432 a partir dele) |
| `/oficina/apigw/api_id` | String | id do HTTP API | lambda-auth |
| `/oficina/apigw/vpc_link_id` | String | id do VPC Link | informativo |
| `/oficina/apigw/vpc_link_integration_id` | String | id da integração HTTP_PROXY via VPC Link (listener **prd**) **com** o mapeamento de contexto (`X-Perfil`/`X-Sub`/`X-Documento`); há uma segunda integração, sem mapeamento, usada pelas rotas públicas | lambda-auth (alvo de `ANY /api/v1/{proxy+}`) |
| `/oficina/eks/cluster_name` | String | `oficina-eks` | CD do oficina-app |
| `/oficina/ecr/repository_url` | String | URL completa do ECR | CD do oficina-app |

## O que este repositório CRIA no Secrets Manager (texto puro, nunca JSON)

| Segredo | Origem do valor | Observação |
|---|---|---|
| `oficina/jwt_secret` | GitHub Secret `JWT_SECRET` → `TF_VAR_jwt_secret` (≥ 32 chars) | Lambda emite, API valida: os dois leem este valor |
| `oficina/newrelic_license_key` | `TF_VAR_newrelic_license_key` quando `newrelic_habilitado = true`; senão placeholder `NEW-RELIC-DESLIGADO` | **Sempre existe** (decisão D2): o CD do oficina-app falha se faltar |

`oficina/db_password` é do `oficina-infra-db`.

## Roles OIDC

| Role | Criada por | Assumida por | Vira |
|---|---|---|---|
| `oficina-gha-infra` | `scripts/bootstrap.sh` | `oficina-infra-k8s`, `oficina-infra-db` (`main`, `develop`) | secret `AWS_TERRAFORM_ROLE_ARN` nos dois |
| `oficina-gha-deploy` | Terraform daqui | `oficina-app` (`main`, `develop`) | secret `AWS_DEPLOY_ROLE_ARN` |
| `oficina-gha-lambda` | Terraform daqui | `oficina-lambda-auth` (`main`, `develop`) | secret `AWS_LAMBDA_ROLE_ARN` |

Trust escopada por branch: o `sub` de `pull_request` **não** assume nenhuma delas.

## Rotas no API Gateway

| Rota | Criada por | Authorizer |
|---|---|---|
| `GET /health` | **este repo** | — |
| `GET /swagger`, `GET /swagger/{proxy+}` | **este repo** | — |
| `POST /api/v1/ordens-servico/{id}/orcamento/aprovacao` | **este repo** | — (webhook protegido por `X-Webhook-Token` na API) |
| `POST /auth/cliente`, `POST /auth/admin` | oficina-lambda-auth | — |
| `ANY /api/v1/{proxy+}` | oficina-lambda-auth | Lambda Authorizer |

Este repositório **não** cria as três últimas. Duas `route_key` iguais em states diferentes
dão `ConflictException`.

## Throttling de `POST /auth/*` — requisito do lambda-auth, com uma ressalva (D1)

`route_settings` de um stage só aceita rotas que **existem**; `POST /auth/*` nasce no
`oficina-lambda-auth`, que roda depois. Por isso o throttling (10 rps, burst 20) fica atrás
de `throttling_auth_habilitado` (default `false`). Sequência:

1. `oficina-infra-k8s` apply (flag `false`) → `infra-db` → `lambda-auth` apply.
2. `gh variable set THROTTLING_AUTH_HABILITADO --body true --repo lcr-thiago-fernandes/oficina-infra-k8s`
3. Re-executar o CD deste repositório em `main` (`gh workflow run cd.yml --ref main`).

Antes de destruir o `lambda-auth`, volte a flag para `false` e reaplique (ou destrua tudo na
ordem inversa de uma vez — o stage some junto com o API).

## Exposição

| Item | Valor |
|---|---|
| Container | `8080` |
| NodePort prd → listener NLB `:80` → **API Gateway** | `30080` |
| NodePort hml → listener NLB `:81` (só dentro da VPC, D3) | `30081` |
| Health check dos target groups | `GET /health`, HTTP 200, a cada 10 s |
| Security groups | `sg-vpclink →(80/81)→ sg-nlb →(30080/30081)→ sg-nodes` (D4) |
| Duas integrações HTTP_PROXY | `vpc_link` (rota protegida, com headers `X-Perfil`/`X-Sub`/`X-Documento` de `$context.authorizer.*` — a API revalida o JWT) e `vpc_link_publica` (rotas públicas, sem mapeamento de contexto) |

## O que este repositório EXIGE dos demais

| Repo | Item |
|---|---|
| oficina-app | Service `NodePort` (não `LoadBalancer`), `nodePort` 30080/30081, `/health` respondendo 200 |
| oficina-lambda-auth | Não criar stage, VPC Link nem integração; usar `/oficina/apigw/vpc_link_integration_id` como alvo da rota protegida |
| oficina-infra-db | Descobrir VPC/subnets/SG dos nós pelo SSM acima; publicar `/oficina/db/endpoint` (só hostname) e `/oficina/db/security_group_id`; criar `oficina/db_password` |
