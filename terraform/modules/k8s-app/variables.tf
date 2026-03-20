variable "app_name" {
  description = "Application name — used for all K8s resource names and labels"
  type        = string
  default     = "react-app"
}

variable "namespace" {
  description = "Kubernetes namespace to create and deploy into"
  type        = string
  default     = "webapp"
}

variable "replicas" {
  description = "Minimum pod replicas (HPA min_replicas and PDB min_available)"
  type        = number
  default     = 2
}

variable "ingress_host" {
  description = "Hostname for Ingress rule — add to /etc/hosts pointing at 127.0.0.1"
  type        = string
  default     = "webapp.local"
}

# ── Registry credentials ───────────────────────────────────────────────────────
# Used to create the kubernetes.io/dockerconfigjson pull secret.
# Injected via: export TF_VAR_registry_username / TF_VAR_registry_password
variable "registry_username" {
  description = "GitLab deploy token username (read_registry scope only)"
  type        = string
  sensitive   = true
}

variable "registry_password" {
  description = "GitLab deploy token password"
  type        = string
  sensitive   = true
}
