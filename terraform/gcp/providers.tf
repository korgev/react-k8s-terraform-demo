# ─────────────────────────────────────────────────────────────────────────────
# GCP Provider Configuration — feature/gke branch
# Kubernetes/Helm providers use direct token auth (not kubeconfig exec plugin)
# This is the production-grade pattern for GKE + Terraform
# ─────────────────────────────────────────────────────────────────────────────

provider "google" {
  credentials = file(var.gcp_sa_key_path)
  project     = var.gcp_project_id
  region      = var.gcp_region
}

# Read cluster details from GKE module outputs
data "google_client_config" "default" {}

data "google_container_cluster" "this" {
  name     = var.gcp_cluster_name
  location = var.gcp_region
  project  = var.gcp_project_id
}

# Direct token auth — no exec plugin, no kubeconfig needed
# This is the recommended pattern for GKE + Terraform
provider "kubernetes" {
  host                   = "https://${data.google_container_cluster.this.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(
    data.google_container_cluster.this.master_auth[0].cluster_ca_certificate
  )
}

provider "helm" {
  kubernetes {
    host                   = "https://${data.google_container_cluster.this.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(
      data.google_container_cluster.this.master_auth[0].cluster_ca_certificate
    )
  }
}
