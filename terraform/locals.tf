data "aws_availability_zones" "disponiveis" {
  state = "available"
}

data "aws_caller_identity" "atual" {}

locals {
  cluster_name = "${var.project}-eks"
  azs          = slice(data.aws_availability_zones.disponiveis.names, 0, 2)

  nome_role_infra  = "${var.project}-gha-infra"
  nome_role_deploy = "${var.project}-gha-deploy"
  nome_role_lambda = "${var.project}-gha-lambda"
  nome_api         = "${var.project}-http-api"

  # Ambientes no MESMO cluster: um NodePort e um listener do NLB por ambiente.
  # O API Gateway integra so com prd (decisao D3).
  ambientes = {
    prd = { nodeport = var.nodeport_prd, porta_listener = 80 }
    hml = { nodeport = var.nodeport_hml, porta_listener = 81 }
  }

  newrelic_placeholder = "NEW-RELIC-DESLIGADO"

  tags = {
    Project   = var.project
    ManagedBy = "Terraform"
    Repo      = "oficina-infra-k8s"
    Fase      = "fase-3"
  }
}
