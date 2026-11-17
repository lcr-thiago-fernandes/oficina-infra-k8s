# Fase 4 (design, secao 9): alertas da saga, na MESMA politica Oficina-Prod (o workflow de
# e-mail ja filtra por ela). Atributos/valores conferidos nos produtores (README, Fase 4).
# Sem filtro por appName, pela mesma razao do alerta de falha de OS da Fase 3: o nome do
# evento customizado ja e unico da aplicacao.
# "Fila DLQ com mensagens" NAO esta aqui: e alarme CloudWatch (terraform/alarmes-dlq.tf).

# Compensacao disparada = so o INICIO da compensacao. Com compensacao = true o produtor grava o
# passo que a dispara (resultado 'Falha': GerarOrcamento, AprovarOrcamento, ConfirmarPagamento,
# EnfileirarExecucao, EstornarPagamento de pagamento tardio) e tambem o desfecho ('Compensado' ou
# 'CompensacaoFalhou'). O cancelamento pedido pelo atendente e um passo unico (Cancelamento/
# Compensado: inicio e desfecho juntos). Filtro = Falha OU Cancelamento: um fluxo de estorno gera
# UM sinal e o Critical de CompensacaoFalhou nao e duplicado. uniqueCount conta sagas, nao linhas.
# Warning: faz parte do fluxo (ex.: cliente rejeitou o orcamento), mas pede olho.
resource "newrelic_nrql_alert_condition" "saga_compensacao" {
  policy_id                    = newrelic_alert_policy.oficina_prod.id
  name                         = "Oficina-Saga-Prod-Compensacao-Warning"
  type                         = "static"
  description                  = "Uma saga da OS iniciou compensacao (compensacao = true com resultado 'Falha', ou cancelamento)."
  runbook_url                  = "${var.runbook_base_url}#compensacao-da-saga"
  enabled                      = true
  violation_time_limit_seconds = 259200
  aggregation_window           = 60
  aggregation_method           = "event_flow"
  aggregation_delay            = 120

  nrql {
    query = "SELECT uniqueCount(ordemServicoId) FROM SagaOrdemServico WHERE compensacao IS true AND (resultado = 'Falha' OR passo = 'Cancelamento')"
  }

  warning {
    operator              = "above"
    threshold             = 0
    threshold_duration    = 60
    threshold_occurrences = "at_least_once"
  }
}

# Compensacao que NAO fechou: EstornoFalhou recebido pela saga (fica em Compensando,
# intervencao manual).
resource "newrelic_nrql_alert_condition" "saga_compensacao_falhou" {
  policy_id                    = newrelic_alert_policy.oficina_prod.id
  name                         = "Oficina-Saga-Prod-CompensacaoFalhou-Critical"
  type                         = "static"
  description                  = "SagaOrdemServico com resultado = 'CompensacaoFalhou' (estorno falhou; saga parada em Compensando)."
  runbook_url                  = "${var.runbook_base_url}#compensacao-ou-estorno-falhou"
  enabled                      = true
  violation_time_limit_seconds = 259200
  aggregation_window           = 60
  aggregation_method           = "event_flow"
  aggregation_delay            = 120

  nrql {
    query = "SELECT count(*) FROM SagaOrdemServico WHERE resultado = 'CompensacaoFalhou'"
  }

  critical {
    operator              = "above"
    threshold             = 0
    threshold_duration    = 60
    threshold_occurrences = "at_least_once"
  }
}

# Lado do Billing: estorno pedido pela saga que falhou (etapa EstornoFalhou) ou estorno
# automatico de pagamento tardio/duplicado que falhou (EstornoAutomatico + Falha) — este
# ultimo nao passa pela saga, entao so este alerta o pega.
# DECISAO: os dois Criticals ficam separados. Uma falha de estorno pedido pela saga abre DOIS
# incidentes (CompensacaoFalhou na saga + EstornoFalhou no Billing), o que e esperado e esta
# documentado no README e no runbook. Fundir perderia o EstornoAutomatico, que nao tem evento
# de saga.
resource "newrelic_nrql_alert_condition" "billing_estorno_falhou" {
  policy_id                    = newrelic_alert_policy.oficina_prod.id
  name                         = "Oficina-Billing-Prod-EstornoFalhou-Critical"
  type                         = "static"
  description                  = "PagamentoEvento com etapa = 'EstornoFalhou' ou estorno automatico com resultado = 'Falha'."
  runbook_url                  = "${var.runbook_base_url}#compensacao-ou-estorno-falhou"
  enabled                      = true
  violation_time_limit_seconds = 259200
  aggregation_window           = 60
  aggregation_method           = "event_flow"
  aggregation_delay            = 120

  nrql {
    query = "SELECT count(*) FROM PagamentoEvento WHERE etapa = 'EstornoFalhou' OR (etapa = 'EstornoAutomatico' AND resultado = 'Falha')"
  }

  critical {
    operator              = "above"
    threshold             = 0
    threshold_duration    = 60
    threshold_occurrences = "at_least_once"
  }
}
