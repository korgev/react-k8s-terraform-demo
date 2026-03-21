terraform {
  required_version = ">= 1.7.0"

  required_providers {
    # Kind cluster provisioner
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.4"
    }
    # Write kubeconfig to local file
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    # Used in k8s-app module
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }

  # ── Remote state ─────

  backend "http" {
    address        = "http://192.168.2.2/api/v4/projects/1/terraform/state/react-k8s-terraform-demo"
    lock_address   = "http://192.168.2.2/api/v4/projects/1/terraform/state/react-k8s-terraform-demo/lock"
    unlock_address = "http://192.168.2.2/api/v4/projects/1/terraform/state/react-k8s-terraform-demo/lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
    retry_wait_min = 5
  }
}
