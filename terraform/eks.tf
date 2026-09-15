# EKS via modulo oficial v20 (access entries nativos, sem aws-auth). Migrado da Fase 2.
locals {
  politica_admin_cluster = "arn:aws:iam::aws:policy/AmazonEKSClusterAdminPolicy"

  # Decisao D8: acesso deterministico. Nada de "creator admin" (dependeria de QUEM fez o
  # primeiro apply). gha-infra aplica este repo (e precisa do acesso para os helm_release);
  # gha-deploy faz kubectl apply pelo CD do oficina-app; humanos entram por variavel.
  access_entries_fixas = {
    gha_infra = {
      principal_arn = data.aws_iam_role.gha_infra.arn
      policy_associations = {
        admin = {
          policy_arn   = local.politica_admin_cluster
          access_scope = { type = "cluster" }
        }
      }
    }
    gha_deploy = {
      principal_arn = aws_iam_role.gha_deploy.arn
      policy_associations = {
        admin = {
          policy_arn   = local.politica_admin_cluster
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  access_entries_extras = {
    for i, arn in var.cluster_admin_principal_arns : "admin_extra_${i}" => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn   = local.politica_admin_cluster
          access_scope = { type = "cluster" }
        }
      }
    }
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  # Endpoint publico para kubectl do CD e da pessoa; os NOS ficam em subnets privadas.
  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
  }

  cloudwatch_log_group_retention_in_days = var.cluster_log_retention_days

  eks_managed_node_groups = {
    default = {
      instance_types = [var.node_instance_type]
      capacity_type  = "ON_DEMAND"

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size
    }
  }

  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = false
  access_entries                           = merge(local.access_entries_fixas, local.access_entries_extras)

  tags = local.tags
}
