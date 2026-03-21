# Kind Cluster Module
module "kind_cluster" {
  source = "./modules/kind-cluster"

  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version
  kubeconfig_path    = "${path.root}/../kubeconfig"
}

# Providers
# config_path points to kubeconfig written by kind_cluster module at apply time
provider "kubernetes" {
  config_path = "${path.root}/../kubeconfig"
}

provider "helm" {
  kubernetes {
    config_path = "${path.root}/../kubeconfig"
  }
}

# Traefik v3 Ingress Controller

# Chart v39.0.4 ships Traefik Proxy v3.6.9 (latest stable as of March 2026).
# Helm repo: https://traefik.github.io/charts
resource "helm_release" "traefik" {
  depends_on = [module.kind_cluster]

  name             = "traefik"
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = "39.0.4"
  namespace        = "traefik"
  create_namespace = true
  wait             = true
  timeout          = 300

  # Service type
  set {
    name  = "service.type"
    value = "NodePort"
  }

  # Web entrypoint (HTTP)
  # Traefik listens internally on port 8000.
  # hostPort 80 maps container port 80 to the host Mac port 80 via Kind.
  set {
    name  = "ports.web.port"
    value = "8000"
  }

  set {
    name  = "ports.web.hostPort"
    value = "80"
  }

  set {
    name  = "ports.web.nodePort"
    value = "30080"
  }

  # Websecure entrypoint (HTTPS)
  # Traefik listens internally on port 8443.
  set {
    name  = "ports.websecure.port"
    value = "8443"
  }

  set {
    name  = "ports.websecure.hostPort"
    value = "443"
  }

  set {
    name  = "ports.websecure.nodePort"
    value = "30443"
  }

  # Schedule on control-plane node only (labeled ingress-ready=true in Kind config)
  set {
    name  = "nodeSelector.ingress-ready"
    value = "true"
  }

  # Toleration required: control-plane has NoSchedule taint by default
  set {
    name  = "tolerations[0].key"
    value = "node-role.kubernetes.io/control-plane"
  }

  set {
    name  = "tolerations[0].operator"
    value = "Equal"
  }

  set {
    name  = "tolerations[0].effect"
    value = "NoSchedule"
  }

  # IngressClass - modern spec.ingressClassName approach (replaces deprecated annotation)
  # Traefik registers IngressClass "traefik" automatically
  set {
    name  = "ingressClass.enabled"
    value = "true"
  }

  set {
    name  = "ingressClass.isDefaultClass"
    value = "true"
  }

  # Enable Kubernetes Ingress provider
  set {
    name  = "providers.kubernetesIngress.enabled"
    value = "true"
  }

  # Enable access logs for observability
  set {
    name  = "logs.access.enabled"
    value = "true"
  }

  # Disable dashboard public exposure (security)
  set {
    name  = "ingressRoute.dashboard.enabled"
    value = "false"
  }
}

# Kubernetes App Module
# Owns: Namespace, ServiceAccount, Pull Secret, Service, Ingress, HPA, PDB
# Does NOT own: Deployment - managed by GitLab CI/CD pipeline
# Reason: avoids chicken-and-egg (Terraform runs before any image exists in registry)
module "k8s_app" {
  source = "./modules/k8s-app"

  depends_on = [
    module.kind_cluster,
    helm_release.traefik,
  ]

  app_name     = var.app_name
  namespace    = var.namespace
  replicas     = var.replicas
  ingress_host = var.ingress_host

  # Registry pull secret - GitLab deploy token (read_registry scope only)
  # Injected via: export TF_VAR_registry_username / TF_VAR_registry_password
  registry_username = var.registry_username
  registry_password = var.registry_password
}
