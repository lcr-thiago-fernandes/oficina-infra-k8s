variable "region" {
  description = "Regiao AWS."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Prefixo dos recursos e dos caminhos no SSM (mesmo dos outros repositorios)."
  type        = string
  default     = "oficina"
}

variable "github_owner" {
  description = "Owner dos repositorios GitHub autorizados a assumir as roles OIDC."
  type        = string
  default     = "lcr-thiago-fernandes"
}

variable "github_repo_app" {
  description = "Repositorio (sem owner) que assume oficina-gha-deploy."
  type        = string
  default     = "oficina-app"
}

variable "github_repo_lambda_auth" {
  description = "Repositorio (sem owner) que assume oficina-gha-lambda."
  type        = string
  default     = "oficina-lambda-auth"
}

# --- Rede ---
variable "vpc_cidr" {
  description = "CIDR da VPC."
  type        = string
  default     = "10.0.0.0/16"
}

# --- EKS ---
variable "cluster_version" {
  description = "Versao do Kubernetes no EKS. Confira `aws eks describe-cluster-versions` antes do apply."
  type        = string
  default     = "1.33"
}

variable "node_instance_type" {
  description = "Tipo de instancia dos nos (t3.medium comporta a API com o agente APM ligado, 512Mi por pod)."
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "cluster_admin_principal_arns" {
  description = "ARNs (usuarios/roles IAM) que recebem AmazonEKSClusterAdminPolicy alem das roles gha-infra e gha-deploy. Quem aplica da propria maquina precisa estar aqui (decisao D8)."
  type        = list(string)
  default     = []
}

variable "cluster_log_retention_days" {
  description = "Retencao dos logs do control plane do EKS no CloudWatch."
  type        = number
  default     = 14
}

# --- ECR ---
variable "ecr_repository_name" {
  description = "Nome do repositorio ECR da imagem da API (lido pelo CD do oficina-app via SSM)."
  type        = string
  default     = "oficina-api"
}

variable "ecr_keep_last_images" {
  description = "Quantas imagens manter (lifecycle policy)."
  type        = number
  default     = 10
}

# --- Exposicao ---
variable "nodeport_prd" {
  description = "NodePort do Service oficina-api no namespace oficina-prd (contrato com o oficina-app)."
  type        = number
  default     = 30080
}

variable "nodeport_hml" {
  description = "NodePort do Service oficina-api no namespace oficina-hml (contrato com o oficina-app)."
  type        = number
  default     = 30081
}

variable "api_default_throttling_rate_limit" {
  description = "Teto global de requisicoes/s do stage $default (todas as rotas)."
  type        = number
  default     = 200
}

variable "api_default_throttling_burst_limit" {
  type    = number
  default = 500
}

variable "throttling_auth_habilitado" {
  description = "Aplica route_settings de throttling em POST /auth/cliente e POST /auth/admin. So pode ser true DEPOIS do primeiro apply do oficina-lambda-auth (as rotas precisam existir) — decisao D1."
  type        = bool
  default     = false
}

variable "throttling_auth_rate_limit" {
  description = "Requisicoes/s por rota /auth/* (contrato com o oficina-lambda-auth: 10)."
  type        = number
  default     = 10
}

variable "throttling_auth_burst_limit" {
  description = "Burst por rota /auth/* (contrato com o oficina-lambda-auth: 20)."
  type        = number
  default     = 20
}

variable "log_retention_days" {
  description = "Retencao dos access logs do API Gateway."
  type        = number
  default     = 14
}

# --- Segredos ---
variable "jwt_secret" {
  description = "Segredo HS256 compartilhado (oficina/jwt_secret). Minimo 32 caracteres. Informe via TF_VAR_jwt_secret; nunca em tfvars commitado."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.jwt_secret) >= 32
    error_message = "jwt_secret precisa ter pelo menos 32 caracteres (contrato com oficina-app e oficina-lambda-auth)."
  }
}

# --- New Relic (opcional; a conta ainda nao existe) ---
variable "newrelic_habilitado" {
  description = "Instala o nri-bundle no cluster e grava a license key real em oficina/newrelic_license_key. false = segredo com placeholder (decisao D2)."
  type        = bool
  default     = false

  validation {
    condition     = !var.newrelic_habilitado || (var.newrelic_license_key != null && length(coalesce(var.newrelic_license_key, "")) > 0)
    error_message = "Com newrelic_habilitado = true, newrelic_license_key e obrigatoria (TF_VAR_newrelic_license_key)."
  }
}

variable "newrelic_license_key" {
  description = "License key do New Relic (ingest). Ignorada quando newrelic_habilitado = false."
  type        = string
  sensitive   = true
  default     = null
}

variable "metrics_server_chart_version" {
  type    = string
  default = "3.12.2"
}

variable "nri_bundle_chart_version" {
  type    = string
  default = "8.0.26"
}
