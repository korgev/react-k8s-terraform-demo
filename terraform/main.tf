# ─── Kind Cluster Module ──────────────────────────────────────────────────────
module "kind_cluster" {
  source = "./modules/kind-cluster"

  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version
  kubeconfig_path    = "${path.root}/../kubeconfig"
}

# ─── Providers (must come after cluster module creates kubeconfig) ─────────────
# Terraform resolves provider config at plan time using the kubeconfig path.
# The cluster module writes the file; providers read it.
provider "kubernetes" {
  config_path = "${path.root}/../kubeconfig"
}

provider "helm" {
  kubernetes {
    config_path = "${path.root}/../kubeconfig"
  }
}

# ─── Nginx Ingress Controller ─────────────────────────────────────────────────
# Installed once at cluster level — shared by all app namespaces.
# Kind-specific config: NodePort + hostPort so traffic reaches port 80 on host.
resource "helm_release" "nginx_ingress" {
  depends_on = [module.kind_cluster]

  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.10.0"
  namespace        = "ingress-nginx"
  create_namespace = true
  wait             = true
  wait_for_jobs    = true
  timeout          = 300

  set {
    name  = "controller.service.type"
    value = "NodePort"
  }
  set {
    name  = "controller.hostPort.enabled"
    value = "true"
  }
  # Schedule ingress controller only on the node labeled ingress-ready=true
  # (set on control-plane in the Kind cluster config)
  set {
    name  = "controller.nodeSelector.ingress-ready"
    value = "true"
  }
  # Toleration required: control-plane node has NoSchedule taint by default
  set {
    name  = "controller.tolerations[0].key"
    value = "node-role.kubernetes.io/control-plane"
  }
  set {
    name  = "controller.tolerations[0].operator"
    value = "Equal"
  }
  set {
    name  = "controller.tolerations[0].effect"
    value = "NoSchedule"
  }
}

# ─── Kubernetes App Module ────────────────────────────────────────────────────
# Owns: Namespace, ServiceAccount, Pull Secret, Service, Ingress, HPA, PDB
# Does NOT own: Deployment — that is managed by GitLab CI/CD
# Reason: avoids chicken-and-egg (Terraform runs before any image is in registry)
module "k8s_app" {
  source = "./modules/k8s-app"

  depends_on = [
    module.kind_cluster,
    helm_release.nginx_ingress,
  ]

  app_name      = var.app_name
  namespace     = var.namespace
  replicas      = var.replicas
  ingress_host  = var.ingress_host   # webapp.local

  # Registry pull secret — deploy token from GitLab (read_registry scope)
  # Injected via: export TF_VAR_registry_username / TF_VAR_registry_password
  registry_username = var.registry_username
  registry_password = var.registry_password
}
