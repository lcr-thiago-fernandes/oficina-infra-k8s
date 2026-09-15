resource "newrelic_notification_destination" "email" {
  name = "Oficina-Email"
  type = "EMAIL"

  property {
    key   = "email"
    value = var.email_alertas
  }
}

resource "newrelic_notification_channel" "email" {
  name           = "Oficina-Email-Canal"
  type           = "EMAIL"
  destination_id = newrelic_notification_destination.email.id
  product        = "IINT"

  property {
    key   = "subject"
    value = "[Oficina] {{ issueTitle }}"
  }
}

resource "newrelic_workflow" "oficina_prod" {
  name                  = "Oficina-Prod-Workflow"
  muting_rules_handling = "NOTIFY_ALL_ISSUES"

  issues_filter {
    name = "politica-oficina-prod"
    type = "FILTER"

    predicate {
      attribute = "labels.policyIds"
      operator  = "EXACTLY_MATCHES"
      values    = [newrelic_alert_policy.oficina_prod.id]
    }
  }

  destination {
    channel_id = newrelic_notification_channel.email.id
  }
}
