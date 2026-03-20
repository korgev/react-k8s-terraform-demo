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

# ─── Monitoring Namespace ─────────────────────────────────────────
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      "app.kubernetes.io/managed-by"       = "terraform"
      "pod-security.kubernetes.io/enforce" = "privileged" # node-exporter needs privileged
    }
  }
}

# ─── kube-prometheus-stack ───────────────────────────────────────
# Bundles: Prometheus Operator, Prometheus, Alertmanager, Grafana,
#          node-exporter, kube-state-metrics
resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "58.2.2"
  namespace        = kubernetes_namespace.monitoring.metadata[0].name
  create_namespace = false
  wait             = true
  timeout          = 600

  # ── Grafana config ────────────────────────────────────────────
  set {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }
  set {
    name  = "grafana.service.type"
    value = "ClusterIP"  # access via port-forward or ingress
  }
  # Pre-load dashboard for our app namespace
  set {
    name  = "grafana.sidecar.dashboards.enabled"
    value = "true"
  }

  # ── Prometheus retention ──────────────────────────────────────
  set {
    name  = "prometheus.prometheusSpec.retention"
    value = "7d"  # keep 7 days of metrics locally
  }
  set {
    name  = "prometheus.prometheusSpec.resources.requests.memory"
    value = "256Mi"
  }
  set {
    name  = "prometheus.prometheusSpec.resources.limits.memory"
    value = "512Mi"
  }

  # ── Scrape our app namespace ──────────────────────────────────
  set {
    name  = "prometheus.prometheusSpec.podMonitorNamespaceSelector.matchLabels.monitoring"
    value = "true"
  }
  set {
    name  = "prometheus.prometheusSpec.serviceMonitorNamespaceSelector.matchLabels.monitoring"
    value = "true"
  }

  # ── Alertmanager (basic config) ───────────────────────────────
  set {
    name  = "alertmanager.alertmanagerSpec.resources.requests.memory"
    value = "64Mi"
  }

  # ── Kind compatibility — disable PSP (removed in K8s 1.25+) ──
  set {
    name  = "global.rbac.createAggregateClusterRoles"
    value = "true"
  }
}

# ─── Grafana Ingress ──────────────────────────────────────────────
resource "kubernetes_ingress_v1" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class" = "nginx"
    }
  }

  spec {
    rule {
      host = "grafana.local"
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
