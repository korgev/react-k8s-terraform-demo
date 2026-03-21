terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# ARCHITECTURE NOTE:
# This module owns INFRASTRUCTURE resources only.
# The Deployment is managed by GitLab CI/CD (kubernetes/deployment.yaml)
# to avoid the chicken-and-egg problem: Terraform runs before CI has
# pushed any image to the registry.
#
# Terraform owns:  Namespace, ServiceAccount, Pull Secret, Service,
#                  Ingress, HPA, PDB
# CI/CD owns:      Deployment (via kubectl apply + envsubst)
# ─────────────────────────────────────────────────────────────────────────────

# ─── Namespace ────────────────────────────────────────────────────────────────
resource "kubernetes_namespace" "app" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      # monitoring=true enables Prometheus ServiceMonitor discovery
      "monitoring" = "true"
      # Pod Security Admission — baseline blocks privileged pods
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}

# ─── Service Account ──────────────────────────────────────────────────────────
# Dedicated SA per app — principle of least privilege
# automountServiceAccountToken=false: app has no K8s API access needs
resource "kubernetes_service_account" "app" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace.app.metadata[0].name
    labels    = local.labels
  }
  automount_service_account_token = false
}

# ─── Registry Pull Secret ─────────────────────────────────────────────────────
# GitLab deploy token (read_registry scope only) stored as K8s secret.
# Referenced by the Deployment's imagePullSecrets.
# Credentials injected via TF_VAR_registry_* env vars — never hardcoded.
resource "kubernetes_secret" "registry_auth" {
  metadata {
    name      = "${var.app_name}-registry-auth"
    namespace = kubernetes_namespace.app.metadata[0].name
    labels    = local.labels
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "registry.gitlab.com" = {
          username = var.registry_username
          password = var.registry_password
          auth     = base64encode("${var.registry_username}:${var.registry_password}")
        }
      }
    })
  }
}

# ─── Service ──────────────────────────────────────────────────────────────────
# ClusterIP — internal only. All external traffic goes via Ingress.
resource "kubernetes_service" "app" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace.app.metadata[0].name
    labels    = local.labels
  }

  spec {
    type     = "ClusterIP"
    selector = local.selector_labels

    port {
      name        = "http"
      port        = 80
      target_port = 80
      protocol    = "TCP"
    }
  }
}

# ─── Ingress ──────────────────────────────────────────────────────────────────
# Routes webapp.local → service/react-app:80
# nginx-ingress controller installed separately in terraform/main.tf
resource "kubernetes_ingress_v1" "app" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace.app.metadata[0].name
    labels    = local.labels
    annotations = {


      # Uncomment for TLS in production (requires cert-manager):
      # "nginx.ingress.kubernetes.io/ssl-redirect" = "true"
    }
  }

  spec {
    rule {
      host = var.ingress_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.app.metadata[0].name
              port { number = 80 }
            }
          }
        }
      }
    }
  }
}

# ─── Horizontal Pod Autoscaler ────────────────────────────────────────────────
# Scale out when CPU hits 70% average across pods.
# Scoped to the Deployment created by CI — uses name reference only.
resource "kubernetes_horizontal_pod_autoscaler_v2" "app" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace.app.metadata[0].name
    labels    = local.labels
  }

  spec {
    min_replicas = var.replicas
    max_replicas = var.replicas * 3

    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = var.app_name # matches Deployment name in kubernetes/deployment.yaml
    }

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }
  }
}

# ─── Pod Disruption Budget ────────────────────────────────────────────────────
# Guarantees at least 1 pod survives voluntary disruptions
# (node drain, cluster upgrades, rolling updates of the node pool)
resource "kubernetes_pod_disruption_budget_v1" "app" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace.app.metadata[0].name
    labels    = local.labels
  }

  spec {
    min_available = 1
    selector {
      match_labels = local.selector_labels
    }
  }
}

# ─── Locals ───────────────────────────────────────────────────────────────────
locals {
  labels = {
    "app.kubernetes.io/name"       = var.app_name
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/part-of"    = "react-k8s-demo"
  }
  # selector_labels must match Deployment's spec.selector.matchLabels exactly
  selector_labels = {
    "app.kubernetes.io/name" = var.app_name
  }
}
