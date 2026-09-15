# Copie para local.tfvars (ignorado pelo git) para aplicar da propria maquina.
# Segredos SEMPRE por TF_VAR_* (TF_VAR_jwt_secret, TF_VAR_newrelic_license_key), nunca aqui.

region  = "us-east-1"
project = "oficina"

cluster_version    = "1.33"
node_instance_type = "t3.medium"
node_desired_size  = 2
node_min_size      = 1
node_max_size      = 3

# Quem aplica da maquina precisa estar aqui para o helm_release e o kubectl funcionarem (decisao D8):
cluster_admin_principal_arns = ["arn:aws:iam::123456789012:user/SEU_USUARIO"]

# Ligue SO depois do primeiro apply do oficina-lambda-auth (decisao D1):
throttling_auth_habilitado = false

# Ligue quando a conta New Relic existir (exige TF_VAR_newrelic_license_key):
newrelic_habilitado = false
