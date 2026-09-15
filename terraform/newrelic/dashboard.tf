# Um dashboard, seis widgets (design, secao 5). As duas primeiras queries sao as do
# contrato com o oficina-app (evento OrdemServicoEvento, atributos statusNovo,
# statusAnterior, duracaoNoStatusSegundos).
resource "newrelic_one_dashboard" "oficina" {
  name        = "Oficina Mecanica - Operacao"
  permissions = "public_read_only"

  page {
    name = "Visao geral"

    widget_line {
      title  = "Volume diario de OS"
      row    = 1
      column = 1
      width  = 6
      height = 3

      nrql_query {
        query = "SELECT count(*) FROM OrdemServicoEvento WHERE statusNovo = 'Recebida' TIMESERIES 1 day SINCE 30 days ago"
      }
    }

    widget_bar {
      title  = "Tempo medio por status (minutos)"
      row    = 1
      column = 7
      width  = 6
      height = 3

      nrql_query {
        query = "SELECT average(duracaoNoStatusSegundos)/60 AS 'minutos' FROM OrdemServicoEvento WHERE statusAnterior IS NOT NULL FACET statusAnterior SINCE 30 days ago"
      }
    }

    widget_line {
      title  = "Latencia p95 por endpoint (ms)"
      row    = 4
      column = 1
      width  = 6
      height = 3

      nrql_query {
        query = "SELECT percentile(duration, 95) * 1000 FROM Transaction WHERE appName = '${var.app_name}' FACET name TIMESERIES AUTO SINCE 1 hour ago"
      }
    }

    widget_billboard {
      title    = "Taxa de erro (%)"
      row      = 4
      column   = 7
      width    = 6
      height   = 3
      warning  = 2
      critical = 5

      nrql_query {
        query = "SELECT percentage(count(*), WHERE error IS true) FROM Transaction WHERE appName = '${var.app_name}' SINCE 1 hour ago"
      }
    }

    widget_line {
      title  = "CPU e memoria dos pods (oficina-*)"
      row    = 7
      column = 1
      width  = 6
      height = 3

      nrql_query {
        query = "SELECT average(cpuUsedCores) AS 'CPU (cores)', average(memoryWorkingSetBytes)/1e6 AS 'Memoria (MB)' FROM K8sContainerSample WHERE namespaceName LIKE 'oficina-%' FACET podName TIMESERIES AUTO SINCE 1 hour ago"
      }
    }

    widget_table {
      title  = "Saude dos pods"
      row    = 7
      column = 7
      width  = 6
      height = 3

      nrql_query {
        query = "SELECT latest(status) AS 'Status', latest(restartCount) AS 'Restarts', latest(isReady) AS 'Pronto' FROM K8sContainerSample WHERE namespaceName LIKE 'oficina-%' FACET namespaceName, podName SINCE 10 minutes ago"
      }
    }
  }
}
