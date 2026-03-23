variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for cluster and subnet"
  type        = string
  default     = "us-central1"
}

variable "cluster_name" {
  description = "GKE cluster name — used for all resource names"
  type        = string
  default     = "react-k8s-gke"
}

variable "subnet_cidr" {
  description = "Primary CIDR for node subnet"
  type        = string
  default     = "10.0.0.0/24"
}

variable "pods_cidr" {
  description = "Secondary CIDR for pods"
  type        = string
  default     = "10.1.0.0/16"
}

variable "services_cidr" {
  description = "Secondary CIDR for services"
  type        = string
  default     = "10.2.0.0/20"
}

variable "master_cidr" {
  description = "CIDR for GKE control plane (must be /28, no overlap)"
  type        = string
  default     = "10.3.0.0/28"
}

variable "kubeconfig_path" {
  description = "Local path to write the kubeconfig file"
  type        = string
  default     = "../../kubeconfig-gke"
}
