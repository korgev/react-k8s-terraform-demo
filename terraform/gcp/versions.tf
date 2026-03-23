terraform {
  required_version = ">= 1.7.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.24"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }

  # GCS backend — native GCP, built-in locking, versioned
  # No credentials needed — uses gcloud auth application-default
  backend "gcs" {
    bucket = "react-k8s-demo-tfstate"
    prefix = "terraform/gke"
  }
}
