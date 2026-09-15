#!/usr/bin/env bash
# Bootstrap da conta AWS — roda LOCALMENTE, UMA vez, antes do primeiro `terraform init`
# de qualquer repositorio da Fase 3 (decisao D6). Idempotente: pode ser re-executado.
#
# Cria:
#   1. bucket S3 do tfstate (versionado, criptografado, acesso publico bloqueado)
#   2. tabela DynamoDB de lock (os repos usam use_lockfile + dynamodb_table na transicao)
#   3. OIDC provider do GitHub Actions
#   4. role oficina-gha-infra (AdministratorAccess) assumivel por oficina-infra-k8s e
#      oficina-infra-db, branches main e develop -> secret AWS_TERRAFORM_ROLE_ARN nos dois repos
#
# Uso: AWS_PROFILE=... ./scripts/bootstrap.sh
# Windows/Git Bash: export PATH="/c/Program Files/Amazon/AWSCLIV2:$PATH"
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
TF_STATE_BUCKET="${TF_STATE_BUCKET:-oficina-tfstate-fiap-15soat}"
TF_LOCK_TABLE="${TF_LOCK_TABLE:-oficina-tfstate-lock}"
GITHUB_OWNER="${GITHUB_OWNER:-lcr-thiago-fernandes}"
ROLE_INFRA="${ROLE_INFRA:-oficina-gha-infra}"
REPOS_INFRA=("oficina-infra-k8s" "oficina-infra-db")

command -v aws >/dev/null || { echo "ERRO: aws CLI nao encontrado no PATH." >&2; exit 1; }
CONTA=$(aws sts get-caller-identity --query Account --output text)
echo "Conta ${CONTA}, regiao ${AWS_REGION}"

# ---------- 1. bucket ----------
if aws s3api head-bucket --bucket "$TF_STATE_BUCKET" 2>/dev/null; then
  echo "Bucket ${TF_STATE_BUCKET} ja existe."
else
  echo "Criando bucket ${TF_STATE_BUCKET}..."
  if [ "$AWS_REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$TF_STATE_BUCKET" --region "$AWS_REGION" >/dev/null
  else
    aws s3api create-bucket --bucket "$TF_STATE_BUCKET" --region "$AWS_REGION" \
      --create-bucket-configuration "LocationConstraint=${AWS_REGION}" >/dev/null
  fi
fi
aws s3api put-bucket-versioning --bucket "$TF_STATE_BUCKET" --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$TF_STATE_BUCKET" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-public-access-block --bucket "$TF_STATE_BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# ---------- 2. tabela de lock ----------
if aws dynamodb describe-table --table-name "$TF_LOCK_TABLE" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "Tabela ${TF_LOCK_TABLE} ja existe."
else
  echo "Criando tabela ${TF_LOCK_TABLE}..."
  aws dynamodb create-table --table-name "$TF_LOCK_TABLE" --region "$AWS_REGION" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST >/dev/null
  aws dynamodb wait table-exists --table-name "$TF_LOCK_TABLE" --region "$AWS_REGION"
fi

# ---------- 3. OIDC provider ----------
OIDC_ARN="arn:aws:iam::${CONTA}:oidc-provider/token.actions.githubusercontent.com"
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" >/dev/null 2>&1; then
  echo "OIDC provider do GitHub ja existe."
else
  echo "Criando OIDC provider do GitHub..."
  # A AWS valida o certificado do GitHub por si (desde 2023); o thumbprint e exigido pela
  # API mas nao usado para validar. Valores publicados pelo GitHub.
  aws iam create-open-id-connect-provider \
    --url "https://token.actions.githubusercontent.com" \
    --client-id-list "sts.amazonaws.com" \
    --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1" "1c58a3a8518e8759bf075b76b750d4f2df264fcd" >/dev/null
fi

# ---------- 4. role oficina-gha-infra ----------
SUBS=()
for repo in "${REPOS_INFRA[@]}"; do
  SUBS+=("\"repo:${GITHUB_OWNER}/${repo}:ref:refs/heads/main\"" "\"repo:${GITHUB_OWNER}/${repo}:ref:refs/heads/develop\"")
done
SUBS_JSON=$(IFS=,; echo "${SUBS[*]}")

TRUST=$(cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "${OIDC_ARN}" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
        "token.actions.githubusercontent.com:sub": [${SUBS_JSON}]
      }
    }
  }]
}
JSON
)

if aws iam get-role --role-name "$ROLE_INFRA" >/dev/null 2>&1; then
  echo "Role ${ROLE_INFRA} ja existe; atualizando a trust policy."
  aws iam update-assume-role-policy --role-name "$ROLE_INFRA" --policy-document "$TRUST"
else
  echo "Criando role ${ROLE_INFRA}..."
  aws iam create-role --role-name "$ROLE_INFRA" \
    --description "Terraform apply dos repositorios oficina-infra-k8s e oficina-infra-db via GitHub OIDC" \
    --assume-role-policy-document "$TRUST" \
    --tags Key=Project,Value=oficina Key=ManagedBy,Value=bootstrap.sh >/dev/null
fi
# AdministratorAccess: o modulo EKS cria IAM roles/policies, launch templates, KMS, logs;
# enumerar cada acao e fragil. Limitacao registrada no README.
aws iam attach-role-policy --role-name "$ROLE_INFRA" --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"

ROLE_ARN=$(aws iam get-role --role-name "$ROLE_INFRA" --query Role.Arn --output text)
echo
echo "OK. Defina nos repositorios oficina-infra-k8s e oficina-infra-db:"
echo "  gh secret set AWS_TERRAFORM_ROLE_ARN --body \"${ROLE_ARN}\" --repo ${GITHUB_OWNER}/<repo>"
echo "Proximo passo: terraform -chdir=terraform init (neste repositorio)."
