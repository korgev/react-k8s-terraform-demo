output "grafana_url" {
  description = "Grafana URL via Ingress (requires grafana.local in /etc/hosts)"
  value       = "http://grafana.local"
}

output "prometheus_port_forward_cmd" {
  description = "Command to access Prometheus locally"
  value       = "kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring"
}

output "grafana_port_forward_cmd" {
  description = "Command to access Grafana locally (alternative to Ingress)"
  value       = "kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring"
}
