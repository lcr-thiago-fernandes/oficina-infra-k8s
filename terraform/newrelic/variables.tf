variable "newrelic_account_id" {
  description = "Account ID do New Relic (TF_VAR_newrelic_account_id)."
  type        = number
}

variable "newrelic_api_key" {
  description = "User API key (NRAK-...). TF_VAR_newrelic_api_key; nunca em tfvars commitado."
  type        = string
  sensitive   = true
}

variable "email_alertas" {
  description = "Destino das notificacoes de alerta."
  type        = string
}

variable "app_name" {
  description = "Nome da aplicacao no APM (contrato com o oficina-app: 'oficina-api', sem sufixo de ambiente)."
  type        = string
  default     = "oficina-api"
}

variable "cluster_name" {
  description = "Nome do cluster no nri-bundle (global.cluster)."
  type        = string
  default     = "oficina-eks"
}

variable "runbook_base_url" {
  description = "URL do docs/runbooks.md deste repositorio; cada condicao aponta para a propria ancora."
  type        = string
  default     = "https://github.com/lcr-thiago-fernandes/oficina-infra-k8s/blob/main/docs/runbooks.md"
}
