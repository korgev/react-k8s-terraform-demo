variable "cluster_name" {
  description = "Kind cluster name"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version tag for kindest/node image"
  type        = string
  default     = "v1.32.0"
}

variable "kubeconfig_path" {
  description = "Local filesystem path to write the kubeconfig"
  type        = string
  default     = "../../kubeconfig"
}

variable "registry_host" {
  description = "Container registry host:port for containerd insecure registry config"
  type        = string
}
