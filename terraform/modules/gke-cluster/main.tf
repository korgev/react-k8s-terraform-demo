# ─────────────────────────────────────────────────────────────────────────────
# GKE Cluster Module
# Owns: VPC, Subnet, Firewall, Node SA, GKE Autopilot cluster, kubeconfig
# Reuses: k8s-app and monitoring modules from on-prem (unchanged)
# ─────────────────────────────────────────────────────────────────────────────

# ─── VPC Network ──────────────────────────────────────────────────────────────
resource "google_compute_network" "vpc" {
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false
  project                 = var.project_id
}

# ─── Subnet ───────────────────────────────────────────────────────────────────
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.cluster_name}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id
  project       = var.project_id

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }
}

# ─── Firewall — allow internal cluster traffic ─────────────────────────────────
resource "google_compute_firewall" "internal" {
  name    = "${var.cluster_name}-internal"
  network = google_compute_network.vpc.name
  project = var.project_id

  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }

  source_ranges = [var.subnet_cidr, var.pods_cidr, var.services_cidr]
}

# ─── Node Service Account ──────────────────────────────────────────────────────
# Least-privilege SA for GKE nodes
# Separate from Terraform SA — nodes only pull images + write logs/metrics
resource "google_service_account" "gke_node_sa" {
  account_id   = "${var.cluster_name}-node-sa"
  display_name = "GKE Node SA — ${var.cluster_name}"
  project      = var.project_id
}

resource "google_project_iam_member" "node_artifact_registry" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}

resource "google_project_iam_member" "node_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}

resource "google_project_iam_member" "node_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}

# ─── GKE Autopilot Cluster ────────────────────────────────────────────────────
# Autopilot: Google manages nodes, scaling, patching, security
# No node pool config needed — just define workloads
resource "google_container_cluster" "this" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id

  enable_autopilot = true

  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Private nodes — no public IPs on nodes
  # Control plane endpoint is still public for kubectl
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_cidr
  }

  cluster_autoscaling {
    auto_provisioning_defaults {
      service_account = google_service_account.gke_node_sa.email
      oauth_scopes = [
        "https://www.googleapis.com/auth/cloud-platform"
      ]
    }
  }

  # REGULAR channel — stable, tested releases, auto-patched
  release_channel {
    channel = "REGULAR"
  }

  # Workload Identity — pods use GCP SA without key files
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  deletion_protection = false

  depends_on = [
    google_compute_subnetwork.subnet,
    google_service_account.gke_node_sa,
    google_project_iam_member.node_artifact_registry,
    google_project_iam_member.node_logging,
    google_project_iam_member.node_monitoring,
  ]
}

# ─── Write kubeconfig ─────────────────────────────────────────────────────────
resource "local_file" "kubeconfig" {
  content = templatefile("${path.module}/kubeconfig.tpl", {
    cluster_name     = var.cluster_name
    cluster_endpoint = "https://${google_container_cluster.this.endpoint}"
    cluster_ca       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
    project_id       = var.project_id
    region           = var.region
  })
  filename        = var.kubeconfig_path
  file_permission = "0600"
}
