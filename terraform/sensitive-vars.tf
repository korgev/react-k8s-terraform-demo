# ─── Sensitive Variables ──────────────────────────────────────────
# Never set defaults for secrets — always inject via environment:
#   export TF_VAR_grafana_admin_password="yourpassword"
#   export TF_VAR_registry_username="your-deploy-token-username"
#   export TF_VAR_registry_password="your-deploy-token-password"

variable "grafana_admin_password" {
  description = "Grafana admin UI password"
  type        = string
  sensitive   = true
}

variable "registry_username" {
  description = "GitLab deploy token username for image pull secret"
  type        = string
  sensitive   = true
}

variable "registry_password" {
  description = "GitLab deploy token password for image pull secret"
  type        = string
  sensitive   = true
}
