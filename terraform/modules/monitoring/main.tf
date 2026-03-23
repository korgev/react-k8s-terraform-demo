terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
  }
}

# Monitoring Namespace
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      "app.kubernetes.io/managed-by"       = "terraform"
      "pod-security.kubernetes.io/enforce" = "privileged" # node-exporter requires host PID/network access
    }
  }
}

# kube-prometheus-stack v72.6.2
# Official chart from prometheus-community
# Bundles: Prometheus Operator, Prometheus, Alertmanager,
#          Grafana, node-exporter, kube-state-metrics
resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "72.6.2"
  namespace        = kubernetes_namespace.monitoring.metadata[0].name
  create_namespace = false
  wait             = true
  timeout          = 600

  values = [
    file("${path.root}/prometheus-values.yaml")
  ]

  # Grafana password injected separately — never stored in values file
  set_sensitive {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }
}

# Grafana Ingress
# Uses modern ingressClassName field — no deprecated annotations
resource "kubernetes_ingress_v1" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = var.grafana_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "kube-prometheus-stack-grafana"
              port { number = 80 }
            }
          }
        }
      }
    }
  }
}
