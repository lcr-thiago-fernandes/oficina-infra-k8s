output "dashboard_url" {
  value = newrelic_one_dashboard.oficina.permalink
}

output "policy_id" {
  value = newrelic_alert_policy.oficina_prod.id
}

output "condicoes" {
  value = [
    newrelic_nrql_alert_condition.latencia.name,
    newrelic_nrql_alert_condition.taxa_erro.name,
    newrelic_nrql_alert_condition.uptime.name,
    newrelic_nrql_alert_condition.falha_os.name,
    newrelic_nrql_alert_condition.cpu_nos.name,
  ]
}
