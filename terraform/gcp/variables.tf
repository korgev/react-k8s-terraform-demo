# ─── GCP-specific variables ───────────────────────────────────────────────────

variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
  default     = "react-k8s-demo"
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "gcp_cluster_name" {
  description = "GKE cluster name"
  type        = string
  default     = "react-k8s-gke"
}

variable "gcp_sa_key_path" {
  description = "Path to GCP service account key JSON — gitignored"
  type        = string
  default     = "../gke-sa-key.json"
}

variable "gcp_grafana_host" {
  description = "Grafana hostname for GCP Ingress"
  type        = string
  default     = "grafana.webapp.local"
}

variable "ingress_host" {
  description = "App hostname for GCP Ingress"
  type        = string
  default     = "webapp.local"
}

# ─── Shared variables (same as on-prem) ───────────────────────────────────────

variable "app_name" {
  description = "Application name — used for all K8s resource names"
  type        = string
  default     = "react-app"
}

variable "namespace" {
  description = "Kubernetes namespace for the application"
  type        = string
  default     = "webapp"
}

variable "replicas" {
  description = "Minimum number of pod replicas"
  type        = number
  default     = 2
}

variable "grafana_admin_password" {
  description = "Grafana admin UI password — inject via TF_VAR_grafana_admin_password"
  type        = string
  sensitive   = true
}

variable "image_repository" {
  description = "Container image repository path (without tag) — Artifact Registry URL"
  type        = string
  default     = "us-central1-docker.pkg.dev/react-k8s-demo/react-app/react-app"
}
