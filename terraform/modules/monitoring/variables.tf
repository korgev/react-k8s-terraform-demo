variable "grafana_admin_password" {
  description = "Grafana admin UI password — inject via TF_VAR_grafana_admin_password"
  type        = string
  sensitive   = true
}
