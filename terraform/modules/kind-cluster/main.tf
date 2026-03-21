terraform {
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.4"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

# ─── Kind Cluster ────────────────────────────────────────────────
resource "kind_cluster" "this" {
  name           = var.cluster_name
  node_image     = "kindest/node:${var.kubernetes_version}"
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    # Control-plane node:
    # - Labeled ingress-ready so nginx-ingress schedules here
    # - Port mappings expose 80/443 from container to host
    node {
      role = "control-plane"

      kubeadm_config_patches = [
        <<-EOT
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
        EOT
      ]

      extra_port_mappings {
        container_port = 80
        host_port      = 80
        protocol       = "TCP"
      }

      extra_port_mappings {
        container_port = 443
        host_port      = 443
        protocol       = "TCP"
      }
    }

    # Worker node for application workloads
    # Separates app pods from control-plane concerns
    node {
      role = "worker"
    }
  }
}

# ─── Write kubeconfig ─────────────────────────────────────────────
# Saved locally for kubectl and CI/CD use
# 0600 = owner read/write only — kubeconfig contains cluster credentials
resource "local_file" "kubeconfig" {
  content         = kind_cluster.this.kubeconfig
  filename        = var.kubeconfig_path
  file_permission = "0600"
}
