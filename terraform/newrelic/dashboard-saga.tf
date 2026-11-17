# Fase 4 (design, secao 9): dashboard "Saga da OS". Cada atributo/valor abaixo foi conferido
# no codigo dos produtores (README, secao "Fase 4 > Observabilidade"):
#   SagaOrdemServico (oficina-app):     ordemServicoId, numeroOs, passo, resultado, compensacao,
#                                       duracaoMs, estado, motivo (razao de negocio), detalhe (PagamentoId/StatusExecucao)
#   PagamentoEvento (billing-service):  ordemServicoId, numeroOs, etapa, resultado, gateway, valor?, meio?
#   ExecucaoEvento (execucao-service):  ordemServicoId, numeroOs, unidade, statusAnterior, statusNovo,
#                                       resultado, duracaoMinutos?
# Dashboard separado do da Fase 3 (que nao muda): os nomes/queries da Fase 3 seguem citados
# no video e no PDF daquela entrega.
locals {
  apps_saga = "'${var.app_name}', '${var.app_name_billing}', '${var.app_name_execucao}'"
}

resource "newrelic_one_dashboard" "saga" {
  name        = "Oficina Mecanica - Saga da OS"
  permissions = "public_read_only"

  page {
    name = "Saga da OS"

    # Estado ATUAL de cada saga: o evento grava o estado depois da transicao (Registrar vem
    # apos TransitionTo em OrdemServicoSaga), entao latest(estado) por OS e o estado corrente.
    # So estados da SAGA (AguardandoOrcamento..Concluida/Cancelada): a entrega da OS (Entregue)
    # fica fora da saga e nao aparece aqui (ela esta no OrdemServicoEvento, dashboard da Fase 3).
    widget_pie {
      title  = "Sagas por estado atual da saga (7 dias)"
      row    = 1
      column = 1
      width  = 4
      height = 3

      nrql_query {
        query = "SELECT count(*) FROM (SELECT latest(estado) AS 'estadoAtual' FROM SagaOrdemServico FACET ordemServicoId LIMIT MAX) FACET estadoAtual SINCE 7 days ago"
      }
    }

    widget_bar {
      title  = "Passos da saga por resultado"
      row    = 1
      column = 5
      width  = 4
      height = 3

      nrql_query {
        query = "SELECT count(*) FROM SagaOrdemServico FACET passo, resultado SINCE 1 day ago"
      }
    }

    widget_table {
      title  = "Sagas compensadas por motivo"
      row    = 1
      column = 9
      width  = 4
      height = 3

      nrql_query {
        query = "SELECT uniqueCount(ordemServicoId) AS 'Sagas' FROM SagaOrdemServico WHERE compensacao IS true FACET motivo SINCE 7 days ago LIMIT 50"
      }
    }

    widget_bar {
      title  = "Tempo por passo (s, desde o passo anterior): media e p95"
      row    = 4
      column = 1
      width  = 6
      height = 3

      nrql_query {
        query = "SELECT average(duracaoMs) / 1000 AS 'media (s)', percentile(duracaoMs, 95) / 1000 AS 'p95 (s)' FROM SagaOrdemServico FACET passo SINCE 1 day ago"
      }
    }

    widget_line {
      title  = "Throughput por servico (transacoes/min)"
      row    = 4
      column = 7
      width  = 6
      height = 3

      nrql_query {
        query = "SELECT rate(count(*), 1 minute) FROM Transaction WHERE appName IN (${local.apps_saga}) FACET appName TIMESERIES AUTO SINCE 1 hour ago"
      }
    }

    widget_bar {
      title  = "Pagamentos por etapa e resultado (Billing)"
      row    = 7
      column = 1
      width  = 6
      height = 3

      nrql_query {
        query = "SELECT count(*) FROM PagamentoEvento FACET etapa, resultado SINCE 1 day ago"
      }
    }

    widget_bar {
      title  = "Execucoes por status e resultado (Execucao)"
      row    = 7
      column = 7
      width  = 6
      height = 3

      nrql_query {
        query = "SELECT count(*) FROM ExecucaoEvento FACET statusNovo, resultado SINCE 1 day ago"
      }
    }

    widget_billboard {
      title  = "Execucao: da fila a finalizacao (s, media)"
      row    = 10
      column = 1
      width  = 4
      height = 3

      nrql_query {
        query = "SELECT average(segundos) AS 'segundos' FROM (SELECT sum(duracaoMs) / 1000 AS 'segundos', filter(count(*), WHERE passo = 'FinalizarExecucao') AS 'finalizada' FROM SagaOrdemServico WHERE passo IN ('Execucao', 'FinalizarExecucao') AND resultado = 'Sucesso' FACET ordemServicoId LIMIT MAX) WHERE finalizada > 0 SINCE 7 days ago"
      }
    }

    widget_billboard {
      title    = "Falhas de compensacao/estorno (24h)"
      row      = 10
      column   = 5
      width    = 4
      height   = 3
      critical = 1

      nrql_query {
        query = "SELECT count(*) AS 'Saga: CompensacaoFalhou' FROM SagaOrdemServico WHERE resultado = 'CompensacaoFalhou' SINCE 1 day ago"
      }

      nrql_query {
        query = "SELECT count(*) AS 'Billing: estorno falhou' FROM PagamentoEvento WHERE etapa = 'EstornoFalhou' OR (etapa = 'EstornoAutomatico' AND resultado = 'Falha') SINCE 1 day ago"
      }
    }

    widget_markdown {
      title  = "Trace distribuido e mapa de servicos"
      row    = 10
      column = 9
      width  = 4
      height = 3

      text = <<-MD
        **Trace distribuido:** o agente .NET instrumenta o MassTransit; uma OS atravessa
        `${var.app_name}` -> SQS -> `${var.app_name_billing}` / `${var.app_name_execucao}` no mesmo trace.
        Abra *APM & Services* -> `${var.app_name}` -> *Distributed tracing* e localize a OS pelo
        `ordemServicoId`: os eventos dos tres servicos (SagaOrdemServico, PagamentoEvento,
        ExecucaoEvento) carregam esse atributo. O `X-Correlation-Id` so vale dentro do OS Service
        (Billing e Execucao nao o propagam nos eventos que publicam).

        **Mapa de servicos:** *APM & Services* -> `${var.app_name}` -> *Service map*.

        **DLQ:** as filas `*_error` sao monitoradas por alarmes CloudWatch
        (`terraform/alarmes-dlq.tf`), nao por este dashboard.
      MD
    }
  }
}
