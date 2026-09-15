# metrics-server: sem ele o HPA do oficina-app (autoscaling/v2, CPU 60%) fica <unknown>.
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.metrics_server_chart_version

  # Kubelet do EKS usa certificado self-signed.
  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }

  depends_on = [module.eks]
}

# New Relic Kubernetes (nri-bundle): infraestrutura, kube-state-metrics, eventos, logs de
# sistema. Atras de var.newrelic_habilitado ate a conta existir. A license key vai como
# set_sensitive (nao aparece no plan nem no state em claro no diff).
resource "helm_release" "nri_bundle" {
  count = var.newrelic_habilitado ? 1 : 0

  name             = "newrelic-bundle"
  namespace        = "newrelic"
  create_namespace = true
  repository       = "https://helm-charts.newrelic.com"
  chart            = "nri-bundle"
  version          = var.nri_bundle_chart_version
  timeout          = 600

  values = [
    templatefile("${path.module}/helm-values/nri-bundle.yaml.tftpl", {
      cluster_name = module.eks.cluster_name
    })
  ]

  set_sensitive {
    name  = "global.licenseKey"
    value = var.newrelic_license_key
  }

  depends_on = [module.eks, helm_release.metrics_server]
}
