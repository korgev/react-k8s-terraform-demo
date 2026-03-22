# Kind Cluster Module
module "kind_cluster" {
  source = "./modules/kind-cluster"

  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version
  kubeconfig_path    = "${path.root}/../kubeconfig"
}

# Providers
provider "kubernetes" {
  config_path = "${path.root}/../kubeconfig"
}

provider "helm" {
  kubernetes {
    config_path = "${path.root}/../kubeconfig"
  }
}

# Traefik v3 Ingress Controller
# Replaces ingress-nginx which was retired March 2026 (EOL, no security patches).
# Chart v39.0.4 ships Traefik Proxy v3.6.9 (latest stable as of March 2026).
# Uses values file (traefik-values.yaml) instead of individual set blocks
# to avoid Helm type coercion issues with nested maps (nodeSelector).
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

  values = [
    file("${path.module}/traefik-values.yaml")
  ]
}

# Kubernetes App Module
# Owns: Namespace, ServiceAccount, Pull Secret, Service, Ingress, HPA, PDB
# Does NOT own: Deployment - managed by GitLab CI/CD pipeline
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

  registry_username        = var.registry_username
  registry_password        = var.registry_password
  registry_host            = var.registry_host
  enable_catch_all_ingress = var.enable_catch_all_ingress
}
