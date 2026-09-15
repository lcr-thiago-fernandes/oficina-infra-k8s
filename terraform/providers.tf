# Sem credenciais no codigo: ambiente local (aws configure) ou OIDC no CI.
provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}

# Autenticacao dos providers kubernetes/helm por `aws eks get-token` (exec), o padrao do
# modulo EKS: o token de data.aws_eks_cluster_auth vale ~15 min e expira antes de o node
# group e os addons ficarem prontos num primeiro apply. Exige aws CLI v2 no PATH de quem
# aplica (runner ubuntu-latest ja tem; local: ver README). A identidade que roda o apply
# precisa estar nas access entries (decisao D8).
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
  }
}
