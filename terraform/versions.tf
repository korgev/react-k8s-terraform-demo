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

  # ── Remote state (uncomment for team use) ────────────────────────
  # backend "http" {
  #   address        = "https://gitlab.com/api/v4/projects/<PROJECT_ID>/terraform/state/k8s-webapp"
  #   lock_address   = "https://gitlab.com/api/v4/projects/<PROJECT_ID>/terraform/state/k8s-webapp/lock"
  #   unlock_address = "https://gitlab.com/api/v4/projects/<PROJECT_ID>/terraform/state/k8s-webapp/lock"
  #   username       = "gitlab-ci-token"
  #   password       = var.gitlab_token   # injected via TF_VAR_gitlab_token env var
  #   lock_method    = "POST"
  #   unlock_method  = "DELETE"
  # }
}
