# VPC via modulo oficial (migrado da Fase 2). 2 AZs, subnets publicas (NAT) e privadas
# (nos do EKS, NLB interno, VPC Link, Lambda auth-api e RDS — os dois ultimos de outros repos).
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7"

  name = "${var.project}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  # Um unico NAT (custo). E por ele que a oficina-auth-api sai para Secrets Manager e
  # DynamoDB — contrato com o oficina-lambda-auth (sem VPC endpoints).
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  # O oficina-infra-db descobre a VPC por tag (Name) alem do SSM.
  tags = merge(local.tags, { Name = "${var.project}-vpc" })
}
