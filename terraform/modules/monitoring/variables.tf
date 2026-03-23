variable "grafana_admin_password" {
  description = "Grafana admin UI password — inject via TF_VAR_grafana_admin_password"
  type        = string
  sensitive   = true
}

variable "grafana_host" {
  description = "Hostname for Grafana Ingress rule — add to /etc/hosts pointing at 127.0.0.1"
  type        = string
  default     = "grafana.local"
}
