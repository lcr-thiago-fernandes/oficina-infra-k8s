# Fase 4 (design, secao 9): alerta "fila DLQ com mensagens".
#
# Por que CloudWatch e nao New Relic: a conta New Relic NAO tem a integracao AWS (link de
# conta + polling de SQS) configurada neste repositorio, e nenhum servico emite evento
# customizado quando uma mensagem cai na _error (PublishFaults = false nos tres; a falha
# definitiva so move a mensagem). A metrica AWS/SQS ApproximateNumberOfMessagesVisible com
# a dimensao QueueName e o sinal exato e verificavel; os alarmes notificam por SNS (e-mail).
#
# Filas: o MassTransit cria "<fila>_error" para cada receive endpoint. Nomes verificados no
# codigo dos produtores (ver README, secao Fase 4):
#   {prefixo}-oficina-os-saga              oficina-app      NomesMensageria.FilaSaga
#   {prefixo}-oficina-billing-comandos     billing-service  TopologiaSaga.NomeFila
#   {prefixo}-oficina-execucao-comandos    execucao-service NomesMensageria.FilaComandos
# Enquanto a fila nao existir (servicos ainda nao subiram) o alarme fica sem dados e, com
# treat_missing_data = notBreaching, em OK.

locals {
  filas_dlq = {
    os_saga           = "${var.prefixo_ambiente_dlq}-oficina-os-saga_error"
    billing_comandos  = "${var.prefixo_ambiente_dlq}-oficina-billing-comandos_error"
    execucao_comandos = "${var.prefixo_ambiente_dlq}-oficina-execucao-comandos_error"
  }
}

resource "aws_sns_topic" "alertas_dlq" {
  name = "${var.project}-alertas-dlq"
}

# Inscricao por e-mail precisa ser CONFIRMADA pelo destinatario (link no primeiro e-mail).
resource "aws_sns_topic_subscription" "alertas_dlq_email" {
  count = var.email_alertas_dlq == "" ? 0 : 1

  topic_arn = aws_sns_topic.alertas_dlq.arn
  protocol  = "email"
  endpoint  = var.email_alertas_dlq
}

resource "aws_cloudwatch_metric_alarm" "dlq_com_mensagens" {
  for_each = local.filas_dlq

  alarm_name        = "Oficina-Saga-Prod-DLQ-${each.key}-Critical"
  alarm_description = "Mensagens na fila ${each.value}: falha definitiva apos retry/redelivery. Runbook: docs/runbooks.md#fila-dlq-com-mensagens."
  namespace         = "AWS/SQS"
  metric_name       = "ApproximateNumberOfMessagesVisible"
  dimensions = {
    QueueName = each.value
  }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alertas_dlq.arn]
  ok_actions    = [aws_sns_topic.alertas_dlq.arn]
}
