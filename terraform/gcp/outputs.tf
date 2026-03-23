output "gke_cluster_name" {
  description = "GKE cluster name"
  value       = module.gke_cluster.cluster_name
}

output "gke_kubeconfig_path" {
  description = "Path to GKE kubeconfig"
  value       = module.gke_cluster.kubeconfig_path
}

output "artifact_registry_url" {
  description = "Artifact Registry URL for CI/CD pipeline"
  value       = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/react-app"
}

output "gke_region" {
  description = "GCP region"
  value       = module.gke_cluster.region
}

output "next_steps_gcp" {
  description = "Post-apply checklist for GCP"
  value       = <<-EOT

  ✅  GKE cluster deployed!

  Step 1 — Get kubeconfig:
    gcloud container clusters get-credentials react-k8s-gke \
      --region us-central1 --project react-k8s-demo

  Step 2 — Verify cluster:
    kubectl get nodes

  Step 3 — Update CI/CD variables in GitLab:
    GCP_REGISTRY = ${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/react-app
    KUBE_CONFIG_GCP = $(cat kubeconfig-gke | base64 | tr -d '\n')

  Step 4 — Trigger pipeline on feature/gke branch

  Step 5 — Get LoadBalancer IP:
    kubectl get svc -n traefik

  EOT
}
