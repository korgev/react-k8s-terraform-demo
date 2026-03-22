terraform {
  required_version = ">= 1.7.0"

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
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }

  # Remote state via GitLab CE HTTP backend with locking
  # Configure in terraform/backend.hcl (gitignored — see backend.hcl.example)
  # Init: terraform init -backend-config=backend.hcl
  # Credentials via env vars (never in backend.hcl):
  #   TF_HTTP_USERNAME = your-gitlab-username
  #   TF_HTTP_PASSWORD = your-personal-access-token
  backend "http" {}
}
