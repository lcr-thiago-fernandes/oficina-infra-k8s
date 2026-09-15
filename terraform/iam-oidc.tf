# OIDC provider e role oficina-gha-infra sao criados por scripts/bootstrap.sh (antes do
# primeiro apply, ovo-e-galinha do CD) e so LIDOS aqui — decisao D6.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_role" "gha_infra" {
  name = local.nome_role_infra
}

locals {
  github_oidc_host = "token.actions.githubusercontent.com"
  # Trust escopada por BRANCH: so main e develop de cada repositorio (design, secao 7).
  subs_app = [
    "repo:${var.github_owner}/${var.github_repo_app}:ref:refs/heads/main",
    "repo:${var.github_owner}/${var.github_repo_app}:ref:refs/heads/develop",
  ]
  subs_lambda = [
    "repo:${var.github_owner}/${var.github_repo_lambda_auth}:ref:refs/heads/main",
    "repo:${var.github_owner}/${var.github_repo_lambda_auth}:ref:refs/heads/develop",
  ]
  conta = data.aws_caller_identity.atual.account_id
}

data "aws_iam_policy_document" "trust_deploy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:sub"
      values   = local.subs_app
    }
  }
}

data "aws_iam_policy_document" "trust_lambda" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:sub"
      values   = local.subs_lambda
    }
  }
}

# ---------- oficina-gha-deploy: build -> ECR -> kubectl (oficina-app) ----------
resource "aws_iam_role" "gha_deploy" {
  name               = local.nome_role_deploy
  description        = "CD do oficina-app via OIDC: push no ECR, describe do EKS, SSM e segredos de runtime."
  assume_role_policy = data.aws_iam_policy_document.trust_deploy.json
}

data "aws_iam_policy_document" "deploy" {
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # a acao exige "*".
  }

  statement {
    sid    = "EcrPushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]
    resources = [aws_ecr_repository.api.arn]
  }

  # O acesso ao cluster em si vem da access entry (eks.tf); aqui so o describe do kubeconfig.
  statement {
    sid       = "EksDescribe"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster", "eks:ListClusters"]
    resources = ["*"]
  }

  # Exatamente os tres parametros que o cd.yml do oficina-app le.
  statement {
    sid     = "SsmLeitura"
    effect  = "Allow"
    actions = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = [
      "arn:aws:ssm:${var.region}:${local.conta}:parameter/${var.project}/ecr/repository_url",
      "arn:aws:ssm:${var.region}:${local.conta}:parameter/${var.project}/eks/cluster_name",
      "arn:aws:ssm:${var.region}:${local.conta}:parameter/${var.project}/db/endpoint",
    ]
  }

  # Os tres segredos que viram o Secret oficina-api-secret. db_password e criado pelo
  # infra-db (Plano 4), por isso ARN por padrao de nome (sufixo aleatorio do Secrets Manager).
  statement {
    sid     = "SegredosLeitura"
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      aws_secretsmanager_secret.jwt.arn,
      aws_secretsmanager_secret.newrelic_license_key.arn,
      "arn:aws:secretsmanager:${var.region}:${local.conta}:secret:${var.project}/db_password-*",
    ]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "${local.nome_role_deploy}-policy"
  role   = aws_iam_role.gha_deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}

# ---------- oficina-gha-lambda: terraform apply do oficina-lambda-auth ----------
# O Terraform do repo 4 cria roles de execucao, funcoes, SGs, tabela DynamoDB, log groups,
# rotas/authorizer no HTTP API e parametros SSM; le SSM, segredos (Describe) e o state.
# Tudo escopado por nome (oficina-auth-*), pelo id do API e pela key do state.
resource "aws_iam_role" "gha_lambda" {
  name               = local.nome_role_lambda
  description        = "CD do oficina-lambda-auth via OIDC: Lambda, IAM (oficina-auth-*), API Gateway, DynamoDB, SG, logs, SSM, state."
  assume_role_policy = data.aws_iam_policy_document.trust_lambda.json
}

locals {
  tfstate_bucket = "oficina-tfstate-fiap-15soat"
  tfstate_lock   = "oficina-tfstate-lock"
  # Rotas, integracoes e authorizers vivem sob /apis/<id>/...; o GET em /apis/<id> e a leitura do proprio API.
  api_gateway_arns = [
    "arn:aws:apigateway:${var.region}::/apis/${aws_apigatewayv2_api.oficina.id}",
    "arn:aws:apigateway:${var.region}::/apis/${aws_apigatewayv2_api.oficina.id}/*",
  ]
}

data "aws_iam_policy_document" "lambda_estado_iam_lambda" {
  statement {
    sid       = "StateBucketList"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketVersioning"]
    resources = ["arn:aws:s3:::${local.tfstate_bucket}"]
  }

  statement {
    sid       = "StateObjetos"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${local.tfstate_bucket}/lambda-auth/*"]
  }

  statement {
    sid       = "StateLock"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:DescribeTable"]
    resources = ["arn:aws:dynamodb:${var.region}:${local.conta}:table/${local.tfstate_lock}"]
  }

  statement {
    sid    = "IamRolesDasLambdas"
    effect = "Allow"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole",
      "iam:UpdateRoleDescription", "iam:UpdateAssumeRolePolicy",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy", "iam:ListRolePolicies",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole", "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags",
    ]
    resources = ["arn:aws:iam::${local.conta}:role/${var.project}-auth-*"]
  }

  statement {
    sid       = "IamPassRoleParaLambda"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.conta}:role/${var.project}-auth-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["lambda.amazonaws.com"]
    }
  }

  statement {
    sid       = "Lambda"
    effect    = "Allow"
    actions   = ["lambda:*"]
    resources = ["arn:aws:lambda:${var.region}:${local.conta}:function:${var.project}-auth-*"]
  }

  # Layer do New Relic (conta 451483290750) quando newrelic_layer_arn for informado no repo 4.
  statement {
    sid       = "LambdaLayerNewRelic"
    effect    = "Allow"
    actions   = ["lambda:GetLayerVersion"]
    resources = ["arn:aws:lambda:${var.region}:451483290750:layer:*"]
  }
}

data "aws_iam_policy_document" "lambda_apigw_ddb_ec2_logs_ssm" {
  statement {
    sid       = "ApiGatewayRotasEAuthorizer"
    effect    = "Allow"
    actions   = ["apigateway:GET", "apigateway:POST", "apigateway:PUT", "apigateway:PATCH", "apigateway:DELETE"]
    resources = local.api_gateway_arns
  }

  statement {
    sid    = "DynamoDbTentativas"
    effect = "Allow"
    actions = [
      "dynamodb:CreateTable", "dynamodb:DeleteTable", "dynamodb:DescribeTable", "dynamodb:UpdateTable",
      "dynamodb:UpdateTimeToLive", "dynamodb:DescribeTimeToLive", "dynamodb:DescribeContinuousBackups",
      "dynamodb:TagResource", "dynamodb:UntagResource", "dynamodb:ListTagsOfResource",
    ]
    resources = ["arn:aws:dynamodb:${var.region}:${local.conta}:table/${var.project}-auth-tentativas"]
  }

  # Security groups nao tem escopo por nome util; o repo 4 cria o SG da Lambda e adiciona
  # uma regra no SG do RDS (que e do repo 3). Describe e Create/Authorize/Revoke em "*".
  statement {
    sid    = "Ec2SecurityGroups"
    effect = "Allow"
    actions = [
      "ec2:Describe*",
      "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
      "ec2:ModifySecurityGroupRules", "ec2:CreateTags", "ec2:DeleteTags",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "LogsDasLambdas"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy", "logs:DeleteRetentionPolicy",
      "logs:TagLogGroup", "logs:UntagLogGroup", "logs:TagResource", "logs:UntagResource", "logs:ListTagsForResource",
    ]
    resources = ["arn:aws:logs:${var.region}:${local.conta}:log-group:/aws/lambda/${var.project}-auth-*"]
  }

  statement {
    sid       = "LogsDescribe"
    effect    = "Allow"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }

  statement {
    sid       = "SsmLeitura"
    effect    = "Allow"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:DescribeParameters"]
    resources = ["arn:aws:ssm:${var.region}:${local.conta}:parameter/${var.project}/*"]
  }

  statement {
    sid    = "SsmEscritaAuth"
    effect = "Allow"
    actions = [
      "ssm:PutParameter", "ssm:DeleteParameter", "ssm:AddTagsToResource",
      "ssm:RemoveTagsFromResource", "ssm:ListTagsForResource",
    ]
    resources = ["arn:aws:ssm:${var.region}:${local.conta}:parameter/${var.project}/auth/*"]
  }

  # data.aws_secretsmanager_secret faz DescribeSecret + GetResourcePolicy; o VALOR nao e lido pelo Terraform.
  statement {
    sid       = "SegredosDescribe"
    effect    = "Allow"
    actions   = ["secretsmanager:DescribeSecret", "secretsmanager:GetResourcePolicy"]
    resources = ["arn:aws:secretsmanager:${var.region}:${local.conta}:secret:${var.project}/*"]
  }
}

resource "aws_iam_role_policy" "lambda_estado_iam_lambda" {
  name   = "${local.nome_role_lambda}-estado-iam-lambda"
  role   = aws_iam_role.gha_lambda.id
  policy = data.aws_iam_policy_document.lambda_estado_iam_lambda.json
}

resource "aws_iam_role_policy" "lambda_apigw_ddb_ec2_logs_ssm" {
  name   = "${local.nome_role_lambda}-apigw-ddb-ec2-logs-ssm"
  role   = aws_iam_role.gha_lambda.id
  policy = data.aws_iam_policy_document.lambda_apigw_ddb_ec2_logs_ssm.json
}
