output "kubeconfig_path" {
  description = "Absolute path to the generated kubeconfig file"
  value       = module.kind_cluster.kubeconfig_path
}

output "cluster_name" {
  description = "Kind cluster name"
  value       = module.kind_cluster.cluster_name
}

output "app_url" {
  description = "Local application URL (add webapp.local to /etc/hosts first)"
  value       = "http://webapp.local"
}

output "grafana_url" {
  description = "Grafana URL via Ingress (add grafana.local to /etc/hosts first)"
  value       = module.monitoring.grafana_url
}

output "grafana_port_forward_cmd" {
  description = "Grafana access via port-forward (alternative to Ingress)"
  value       = module.monitoring.grafana_port_forward_cmd
}

output "prometheus_port_forward_cmd" {
  description = "Prometheus access via port-forward"
  value       = module.monitoring.prometheus_port_forward_cmd
}

output "next_steps" {
  description = "Post-apply checklist"
  value       = <<-EOT

  ✅  Cluster, app, and monitoring deployed!

  Step 1 — DNS:
    echo "127.0.0.1 webapp.local grafana.local" | sudo tee -a /etc/hosts

  Step 2 — GitLab KUBE_CONFIG variable:
    cat kubeconfig | base64 | tr -d '\n' | pbcopy
    Paste as KUBE_CONFIG in GitLab Settings -> CI/CD -> Variables (Protected + Masked)

  Step 3 — Open app:
    open http://webapp.local
    open http://grafana.local  (admin / your grafana password)

  Step 4 — Public URL (ngrok launchd service — already running):
    https://mervin-tetrahydric-dwayne.ngrok-free.dev

  EOT
}

output "image_repository" {
  description = "Container image repository path (used in CI/CD pipeline)"
  value       = var.image_repository
}
