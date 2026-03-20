variable "cluster_name" {
  description = "Kind cluster name"
  type        = string
  default     = "react-k8s-cluster"
}

variable "kubernetes_version" {
  description = "Kubernetes version — must match a kindest/node image tag"
  type        = string
  default     = "v1.29.2"
}

variable "app_name" {
  description = "Application name — used for all K8s resource names and labels"
  type        = string
  default     = "react-app"
}

variable "namespace" {
  description = "Kubernetes namespace for the application"
  type        = string
  default     = "webapp"
}

variable "ingress_host" {
  description = "Hostname for the Ingress rule — add to /etc/hosts pointing to 127.0.0.1"
  type        = string
  default     = "webapp.local"
}

variable "image_repository" {
  description = "Container image repository path (without tag). Example: registry.gitlab.com/user/project/react-app"
  type        = string
}

variable "replicas" {
  description = "Minimum number of pod replicas (HPA may scale higher)"
  type        = number
  default     = 2
}
