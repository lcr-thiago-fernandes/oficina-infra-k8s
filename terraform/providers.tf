# Sem credenciais no codigo: ambiente local (aws configure) ou OIDC no CI.
provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}

# Autenticacao dos providers kubernetes/helm derivada do cluster (lida em tempo de apply,
# porque o name depende de module.eks). O token e da identidade que roda o apply — ela
# precisa estar nas access entries (decisao D8).
data "aws_eks_cluster" "este" {
  name = module.eks.cluster_name
}

data "aws_eks_cluster_auth" "este" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.este.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.este.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.este.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.este.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.este.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.este.token
  }
}
