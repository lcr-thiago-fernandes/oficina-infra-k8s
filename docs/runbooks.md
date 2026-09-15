# Runbooks dos alertas

Cada condição do New Relic (`terraform/newrelic/alertas.tf`) aponta para uma âncora deste arquivo.
Antes de tudo: `aws eks update-kubeconfig --region us-east-1 --name oficina-eks`.

## Tempo de resposta

**Alerta:** `Oficina-API-Prod-Latencia-Critical` — p95 > 500 ms por 5 min.

1. No APM (`oficina-api`), aba *Transactions*: qual endpoint puxou o p95? Consulte também *Databases* (query lenta) — `log_min_duration_statement = 500` no RDS registra as demoradas.
2. `kubectl -n oficina-prd get hpa` — o HPA já está no teto (10 réplicas)? Se sim, é limite de nó (ver *CPU do cluster*).
3. `kubectl -n oficina-prd top pods` — algum pod perto de 512Mi (GC agressivo)?
4. Ação típica: escalar o node group (`node_max_size`) ou investigar a query no Performance Insights do RDS.

## Taxa de erro

**Alerta:** `Oficina-API-Prod-TaxaErro-Critical` — > 5% de transações com erro por 5 min.

1. APM → *Errors inbox*: `error.class` e `transactionName` dominantes.
2. `kubectl -n oficina-prd logs deploy/oficina-api --since=15m | grep -i '"Level":"Error"'`; correlacione por `correlationId`/`trace.id`.
3. Erros de conexão com o banco → confira o SG do RDS (`/oficina/db/security_group_id`) e o segredo `oficina/db_password`.
4. Erros 401 em massa → `oficina/jwt_secret` divergente entre Lambda e API (rotação sem redeploy dos dois lados).

## Uptime

**Alerta:** `Oficina-API-Prod-Uptime-Critical` — nenhuma transação por 5 min.

1. `curl -i https://<api_endpoint>/health` (output `api_endpoint`). 5xx do API Gateway = integração; timeout = NLB/targets.
2. Target group: `aws elbv2 describe-target-health --target-group-arn <oficina-api-prd>` — targets *unhealthy* → `kubectl -n oficina-prd get pods` e `kubectl -n oficina-prd get svc oficina-api` (nodePort 30080?).
3. Pods `CrashLoopBackOff` → `kubectl -n oficina-prd describe pod` e logs do container anterior (`--previous`).
4. Se tudo saudável e sem tráfego real: falso positivo esperado fora do horário de demonstração — o `/health` do NLB deveria manter o sinal; verifique o agente (`NEW_RELIC_LICENSE_KEY` placeholder = New Relic desligado).

## Falha no processamento de OS

**Alerta:** `Oficina-OS-Prod-FalhaProcessamento-Critical` — `OrdemServicoEvento` com `resultado = 'Falha'`.

1. `SELECT * FROM OrdemServicoEvento WHERE resultado = 'Falha' SINCE 1 hour ago` — `numeroOs`, `statusAnterior`.
2. Logs da API filtrados pelo `numeroOs`; transição inválida (422) **não** gera esse evento — se gerou, é bug no filtro de telemetria.
3. Confira `os.historico_status` no banco para a OS (`SELECT * FROM os.historico_status WHERE ordem_servico_id = ...`).

## CPU do cluster

**Alerta:** `Oficina-EKS-Prod-CPU-Warning` — CPU média dos nós > 80% por 10 min.

1. `kubectl top nodes`; `kubectl get pods -A --field-selector=status.phase=Pending` (pods sem nó?).
2. Suba `node_max_size`/`node_desired_size` em `terraform/variables.tf` (ou `-var`) e aplique pelo CD.
3. Se for só hml consumindo, reduza réplicas em `oficina-hml` (`kubectl -n oficina-hml scale deploy/oficina-api --replicas=1`).
