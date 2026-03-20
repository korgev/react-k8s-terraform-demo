# ─── Monitoring Stack ─────────────────────────────────────────────
# Prometheus + Grafana via kube-prometheus-stack Helm chart
module "monitoring" {
  source = "./modules/monitoring"

  depends_on = [
    module.kind_cluster,
    helm_release.nginx_ingress,
  ]

  grafana_admin_password = var.grafana_admin_password
}
