# Segredos compartilhados, em TEXTO PURO (contrato: o CD do oficina-app e a
# oficina-auth-api leem com `--query SecretString --output text`; JSON quebraria ambos).
# recovery_window_in_days = 0: destroy imediato, senao o nome fica bloqueado por 7-30 dias
# e o proximo apply falha com "scheduled for deletion".
# oficina/db_password NAO e daqui: pertence ao oficina-infra-db (Plano 4).

resource "aws_secretsmanager_secret" "jwt" {
  name                    = "${var.project}/jwt_secret"
  description             = "Segredo HS256: oficina-auth emite, oficina-api valida. Texto puro, >= 32 chars."
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "jwt" {
  secret_id     = aws_secretsmanager_secret.jwt.id
  secret_string = var.jwt_secret
}

# Criado SEMPRE (decisao D2): o CD do oficina-app falha se este segredo nao existir.
# Sem conta New Relic o valor e um placeholder; o agente .NET rejeita a licenca e se
# desliga sozinho, a API sobe normalmente.
resource "aws_secretsmanager_secret" "newrelic_license_key" {
  name                    = "${var.project}/newrelic_license_key"
  description             = "License key do New Relic (ingest). Placeholder enquanto newrelic_habilitado = false."
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "newrelic_license_key" {
  secret_id     = aws_secretsmanager_secret.newrelic_license_key.id
  secret_string = var.newrelic_habilitado ? var.newrelic_license_key : local.newrelic_placeholder
}
