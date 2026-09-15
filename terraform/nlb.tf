# Terraform e dono do NLB (design, secao 4; ADR-016): o VPC Link do HTTP API exige o ARN do
# listener no apply, e um Service LoadBalancer do Kubernetes so o teria depois do deploy.
# O oficina-app publica Service NodePort (30080 prd / 30081 hml) e este arquivo anexa o
# ASG do node group a um target group por porta.
#
# Cadeia de security groups (decisao D4):
#   sg-vpclink --(80/81)--> sg-nlb --(30080/30081)--> sg-nodes (EKS)
# O SG do NLB cobre tambem os health checks; preserve_client_ip = false garante que a
# origem vista pelo no e a ENI do NLB (a referencia por SG e inequivoca).

resource "aws_security_group" "vpclink" {
  name        = "${var.project}-vpclink-sg"
  description = "ENIs do VPC Link do API Gateway: saida so para o NLB interno"
  vpc_id      = module.vpc.vpc_id
  tags        = { Name = "${var.project}-vpclink-sg" }
}

resource "aws_security_group" "nlb" {
  name        = "${var.project}-nlb-sg"
  description = "NLB interno: entrada do VPC Link, saida para os NodePorts dos nos"
  vpc_id      = module.vpc.vpc_id
  tags        = { Name = "${var.project}-nlb-sg" }
}

resource "aws_vpc_security_group_egress_rule" "vpclink_para_nlb" {
  for_each = local.ambientes

  security_group_id            = aws_security_group.vpclink.id
  description                  = "Listener ${each.key} do NLB"
  ip_protocol                  = "tcp"
  from_port                    = each.value.porta_listener
  to_port                      = each.value.porta_listener
  referenced_security_group_id = aws_security_group.nlb.id
}

resource "aws_vpc_security_group_ingress_rule" "nlb_recebe_do_vpclink" {
  for_each = local.ambientes

  security_group_id            = aws_security_group.nlb.id
  description                  = "Do VPC Link (${each.key})"
  ip_protocol                  = "tcp"
  from_port                    = each.value.porta_listener
  to_port                      = each.value.porta_listener
  referenced_security_group_id = aws_security_group.vpclink.id
}

# Homologacao (:81) nao passa pelo API Gateway (decisao D3): so e alcancavel de dentro da
# VPC (pods, port-forward, bastiao). Sem esta regra o listener hml nao aceitaria ninguem.
resource "aws_vpc_security_group_ingress_rule" "nlb_hml_da_vpc" {
  security_group_id = aws_security_group.nlb.id
  description       = "Listener hml (:81) a partir da VPC"
  ip_protocol       = "tcp"
  from_port         = local.ambientes.hml.porta_listener
  to_port           = local.ambientes.hml.porta_listener
  cidr_ipv4         = module.vpc.vpc_cidr_block
}

resource "aws_vpc_security_group_egress_rule" "nlb_para_nos" {
  for_each = local.ambientes

  security_group_id            = aws_security_group.nlb.id
  description                  = "NodePort ${each.key} (trafego e health check)"
  ip_protocol                  = "tcp"
  from_port                    = each.value.nodeport
  to_port                      = each.value.nodeport
  referenced_security_group_id = module.eks.node_security_group_id
}

# Regra no SG dos nos (criado pelo modulo EKS): recurso separado, nunca inline.
resource "aws_vpc_security_group_ingress_rule" "nos_recebem_do_nlb" {
  for_each = local.ambientes

  security_group_id            = module.eks.node_security_group_id
  description                  = "NodePort ${each.key} a partir do NLB interno"
  ip_protocol                  = "tcp"
  from_port                    = each.value.nodeport
  to_port                      = each.value.nodeport
  referenced_security_group_id = aws_security_group.nlb.id
}

resource "aws_lb" "interno" {
  name               = "${var.project}-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = module.vpc.private_subnets
  security_groups    = [aws_security_group.nlb.id]

  enable_cross_zone_load_balancing = true
}

resource "aws_lb_target_group" "api" {
  for_each = local.ambientes

  name        = "${var.project}-api-${each.key}"
  port        = each.value.nodeport
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = module.vpc.vpc_id

  preserve_client_ip   = "false"
  deregistration_delay = 30

  # Service NodePort com externalTrafficPolicy Cluster: qualquer no responde, mesmo sem
  # pod local; o health check em /health acompanha a readiness da API.
  health_check {
    protocol            = "HTTP"
    path                = "/health"
    port                = "traffic-port"
    matcher             = "200"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "api" {
  for_each = local.ambientes

  load_balancer_arn = aws_lb.interno.arn
  port              = each.value.porta_listener
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api[each.key].arn
  }
}

# Anexa o ASG do node group aos dois target groups: novos nos entram sozinhos.
resource "aws_autoscaling_attachment" "api" {
  for_each = local.ambientes

  autoscaling_group_name = module.eks.eks_managed_node_groups["default"].node_group_autoscaling_group_names[0]
  lb_target_group_arn    = aws_lb_target_group.api[each.key].arn
}
