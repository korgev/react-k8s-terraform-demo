terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.24"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}
