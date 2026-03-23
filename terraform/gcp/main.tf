# ─────────────────────────────────────────────────────────────────────────────
# GCP Root Configuration
# Used on feature/gke branch only
# On-prem (main branch) uses main.tf + monitoring.tf instead
# ─────────────────────────────────────────────────────────────────────────────

# ─── GKE Cluster Module ───────────────────────────────────────────────────────
module "gke_cluster" {
  source = "../modules/gke-cluster"

  project_id      = var.gcp_project_id
  region          = var.gcp_region
  cluster_name    = var.gcp_cluster_name
  kubeconfig_path = "${path.root}/../../kubeconfig-gke"
}

# ─── Artifact Registry ────────────────────────────────────────────────────────
# Single Docker repository for react-app images
# GKE nodes pull from here via node SA (no credentials needed)
resource "google_artifact_registry_repository" "react_app" {
  provider      = google
  location      = var.gcp_region
  repository_id = "react-app"
  format        = "DOCKER"
  project       = var.gcp_project_id
  description   = "React app Docker images — GKE deployment"
}

# ─── Kubernetes App Module ────────────────────────────────────────────────────
# Reused from on-prem — identical module, different provider config
module "k8s_app" {
  source = "../modules/k8s-app"

  depends_on = [module.gke_cluster]

  app_name  = var.app_name
  namespace = var.namespace
  replicas  = var.replicas

  # Catch-all not needed on GCP — we have a real LoadBalancer IP
  ingress_host             = var.ingress_host
  enable_catch_all_ingress = false

  # Artifact Registry credentials handled by node SA — no pull secret needed
  # But module requires these vars — pass empty (pull secret won't work, that's ok)
  registry_username = "oauth2accesstoken"
  registry_password = ""
  registry_host     = "${var.gcp_region}-docker.pkg.dev"
}

# ─── Monitoring Module ────────────────────────────────────────────────────────
# Reused from on-prem — identical module
module "monitoring" {
  source = "../modules/monitoring"

  depends_on = [module.gke_cluster]

  grafana_admin_password = var.grafana_admin_password
  grafana_host           = var.gcp_grafana_host
}
