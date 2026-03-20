output "kubeconfig_path" {
  description = "Path to the written kubeconfig file"
  value       = local_file.kubeconfig.filename
}

output "kubeconfig" {
  description = "Raw kubeconfig content (sensitive)"
  value       = kind_cluster.this.kubeconfig
  sensitive   = true
}

output "cluster_name" {
  description = "Kind cluster name"
  value       = kind_cluster.this.name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint"
  value       = kind_cluster.this.endpoint
}
