output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.this.name
}

output "cluster_endpoint" {
  description = "GKE cluster API server endpoint"
  value       = google_container_cluster.this.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "GKE cluster CA certificate (base64)"
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "kubeconfig_path" {
  description = "Path to the written kubeconfig file"
  value       = local_file.kubeconfig.filename
}

output "vpc_name" {
  description = "VPC network name"
  value       = google_compute_network.vpc.name
}

output "node_sa_email" {
  description = "GKE node service account email"
  value       = google_service_account.gke_node_sa.email
}

output "region" {
  description = "GCP region"
  value       = var.region
}
