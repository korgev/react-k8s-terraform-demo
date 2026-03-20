output "namespace" {
  description = "Kubernetes namespace created for the app"
  value       = kubernetes_namespace.app.metadata[0].name
}

output "service_name" {
  description = "Kubernetes Service name"
  value       = kubernetes_service.app.metadata[0].name
}

output "ingress_host" {
  description = "Ingress hostname (add to /etc/hosts → 127.0.0.1)"
  value       = var.ingress_host
}

output "pull_secret_name" {
  description = "Name of the registry pull secret created in the namespace"
  value       = kubernetes_secret.registry_auth.metadata[0].name
}

output "service_account_name" {
  description = "Name of the dedicated ServiceAccount"
  value       = kubernetes_service_account.app.metadata[0].name
}
