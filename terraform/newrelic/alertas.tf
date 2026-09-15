# Cinco alertas do design (secao 5). Nomes EXATOS: o vídeo e o PDF de entrega os citam.
# Os alertas baseados em Transaction (latencia, taxa de erro) filtram por appName =
# 'oficina-api' (contrato com o oficina-app); o alerta de falha de OS e um evento
# customizado com nome proprio e unico, entao NAO filtra por appName.
resource "newrelic_alert_policy" "oficina_prod" {
  name                = "Oficina-Prod"
  incident_preference = "PER_CONDITION"
}

locals {
  # So appName (contrato: 'oficina-api' sem sufixo). O label ambiente:prd/hml do agente e uma
  # tag de ENTIDADE, nao um atributo garantido nos eventos Transaction; filtrar por ele aqui
  # poderia silenciar o alerta. hml gera trafego residual e compartilha o nome — aceito.
  filtro_api = "appName = '${var.app_name}'"
}

resource "newrelic_nrql_alert_condition" "latencia" {
  policy_id                    = newrelic_alert_policy.oficina_prod.id
  name                         = "Oficina-API-Prod-Latencia-Critical"
  type                         = "static"
  description                  = "p95 da API acima de 500 ms por 5 minutos."
  runbook_url                  = "${var.runbook_base_url}#tempo-de-resposta"
  enabled                      = true
  violation_time_limit_seconds = 259200
  aggregation_window           = 60
  aggregation_method           = "event_flow"
  aggregation_delay            = 120

  nrql {
    query = "SELECT percentile(duration, 95) * 1000 FROM Transaction WHERE ${local.filtro_api}"
  }

  critical {
    operator              = "above"
    threshold             = 500
    threshold_duration    = 300
    threshold_occurrences = "all"
  }
}

resource "newrelic_nrql_alert_condition" "taxa_erro" {
  policy_id                    = newrelic_alert_policy.oficina_prod.id
  name                         = "Oficina-API-Prod-TaxaErro-Critical"
  type                         = "static"
  description                  = "Mais de 5% das transacoes com erro por 5 minutos."
  runbook_url                  = "${var.runbook_base_url}#taxa-de-erro"
  enabled                      = true
  violation_time_limit_seconds = 259200
  aggregation_window           = 60
  aggregation_method           = "event_flow"
  aggregation_delay            = 120

  nrql {
    query = "SELECT percentage(count(*), WHERE error IS true) FROM Transaction WHERE ${local.filtro_api}"
  }

  critical {
    operator              = "above"
    threshold             = 5
    threshold_duration    = 300
    threshold_occurrences = "all"
  }
}

# Uptime = perda de sinal: nenhuma transacao (nem /health, chamado pelo NLB a cada 10 s) por 5 min.
resource "newrelic_nrql_alert_condition" "uptime" {
  policy_id                      = newrelic_alert_policy.oficina_prod.id
  name                           = "Oficina-API-Prod-Uptime-Critical"
  type                           = "static"
  description                    = "A API deixou de reportar transacoes por 5 minutos (loss of signal)."
  runbook_url                    = "${var.runbook_base_url}#uptime"
  enabled                        = true
  violation_time_limit_seconds   = 259200
  aggregation_window             = 60
  aggregation_method             = "event_flow"
  aggregation_delay              = 120
  expiration_duration            = 300
  open_violation_on_expiration   = true
  close_violations_on_expiration = true

  nrql {
    query = "SELECT count(*) FROM Transaction WHERE ${local.filtro_api}"
  }

  critical {
    operator              = "below"
    threshold             = 1
    threshold_duration    = 300
    threshold_occurrences = "all"
  }
}

resource "newrelic_nrql_alert_condition" "falha_os" {
  policy_id                    = newrelic_alert_policy.oficina_prod.id
  name                         = "Oficina-OS-Prod-FalhaProcessamento-Critical"
  type                         = "static"
  description                  = "Evento de negocio OrdemServicoEvento com resultado = 'Falha'."
  runbook_url                  = "${var.runbook_base_url}#falha-no-processamento-de-os"
  enabled                      = true
  violation_time_limit_seconds = 259200
  aggregation_window           = 60
  aggregation_method           = "event_flow"
  aggregation_delay            = 120

  # Sem filtro por appName: evento custom pode nao carregar o atributo; o nome do evento ja e unico da aplicacao.
  nrql {
    query = "SELECT count(*) FROM OrdemServicoEvento WHERE resultado = 'Falha'"
  }

  critical {
    operator              = "above"
    threshold             = 0
    threshold_duration    = 60
    threshold_occurrences = "at_least_once"
  }
}

resource "newrelic_nrql_alert_condition" "cpu_nos" {
  policy_id                    = newrelic_alert_policy.oficina_prod.id
  name                         = "Oficina-EKS-Prod-CPU-Warning"
  type                         = "static"
  description                  = "CPU media dos nos do EKS acima de 80% por 10 minutos."
  runbook_url                  = "${var.runbook_base_url}#cpu-do-cluster"
  enabled                      = true
  violation_time_limit_seconds = 259200
  aggregation_window           = 60
  aggregation_method           = "event_flow"
  aggregation_delay            = 120

  nrql {
    query = "SELECT average(cpuUsedCores / allocatableCpuCores) * 100 FROM K8sNodeSample WHERE clusterName = '${var.cluster_name}'"
  }

  warning {
    operator              = "above"
    threshold             = 80
    threshold_duration    = 600
    threshold_occurrences = "all"
  }
}
