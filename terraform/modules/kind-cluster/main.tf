terraform {
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.11.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# Kind Cluster
# containerdConfigPatches sets config_path so containerd uses hosts.toml
# for insecure registry config — must be set at cluster creation time
resource "kind_cluster" "this" {
  name           = var.cluster_name
  node_image     = "kindest/node:${var.kubernetes_version}"
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    # Tell containerd to look in /etc/containerd/certs.d for registry config
    containerd_config_patches = [
      <<-TOML
        [plugins."io.containerd.grpc.v1.cri".registry]
          config_path = "/etc/containerd/certs.d"
      TOML
    ]

    # Control-plane node:
    # - Labeled ingress-ready so Traefik schedules here
    # - Port mappings expose 80/443 from container to host Mac
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
    node {
      role = "worker"
    }
  }
}

# Write kubeconfig — 0600 permissions, never committed to git
resource "local_file" "kubeconfig" {
  content         = kind_cluster.this.kubeconfig
  filename        = var.kubeconfig_path
  file_permission = "0600"
}

# Configure insecure registry on all Kind nodes after cluster creation
# hosts.toml tells containerd to use HTTP for local GitLab CE registry
resource "null_resource" "registry_config" {
  depends_on = [kind_cluster.this]

  triggers = {
    cluster_id = kind_cluster.this.id
  }

  provisioner "local-exec" {
    command = <<-BASH
      for node in ${var.cluster_name}-control-plane ${var.cluster_name}-worker; do
        docker exec "$node" mkdir -p /etc/containerd/certs.d/192.168.2.2:5050
        docker exec "$node" sh -c 'cat > /etc/containerd/certs.d/192.168.2.2:5050/hosts.toml << TOML
server = "http://192.168.2.2:5050"

[host."http://192.168.2.2:5050"]
  capabilities = ["pull", "resolve"]
  skip_verify = true
  plain-http = true
TOML'
        docker exec "$node" systemctl restart containerd
        echo "Registry configured on $node"
      done
    BASH
  }
}
