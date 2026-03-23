# ARCHITECTURE.md — Design Decisions & Technical Deep Dive

## Two Deployments

This project implements the task twice — local on-prem and cloud — to demonstrate
both local K8s tooling and managed cloud infrastructure.

| | On-prem (main) | GCP/GKE (feature/gke) |
|---|---|---|
| Cluster | Kind v1.32 (Docker) | GKE Autopilot (managed) |
| Registry | GitLab CE :5050 | GCP Artifact Registry |
| Ingress | Traefik v3 | GCP Cloud LoadBalancer |
| State | GitLab CE HTTP backend | GCS bucket |
| Public URL | ngrok static domain (HTTPS) | Real public IP (HTTP) |
| Monitoring | kube-prometheus-stack | Grafana + Cloud Monitoring |

---

## Stack Overview

| Layer | Technology | Version | Why Chosen |
|---|---|---|---|
| App | React 18 + Vite | 18.x / 5.x | Fast builds, small bundles, modern tooling |
| Container | Docker multi-stage | 28.x | node builder → nginx server, minimal attack surface |
| Web server | nginx (alpine) | 1.25 | Lightweight, non-root, port 8080 |
| Orchestration (on-prem) | Kubernetes via Kind | 1.32 | Local K8s, Docker-native, no CLI needed |
| Orchestration (GCP) | GKE Autopilot | 1.34 | Fully managed nodes, auto-scaling, built-in security |
| IaC | Terraform | 1.7+ | Industry standard, modular, remote state |
| CI/CD | GitLab CE | 18.10 | Self-hosted, full feature set |
| Ingress (on-prem) | Traefik v3 | 3.6.9 | Replaced ingress-nginx (EOL March 2026) |
| Monitoring (on-prem) | kube-prometheus-stack | 72.x | Prometheus + Grafana + Alertmanager |
| Monitoring (GCP) | Grafana + Cloud Monitoring | 8.x | Lightweight, GKE Autopilot built-in metrics |
| Runtime (macOS) | OrbStack | latest | 50-70% less RAM than Docker Desktop on Apple Silicon |
| Public access (on-prem) | ngrok launchd | 3.x | Permanent HTTPS, runs without terminal |
| Public access (GCP) | GCP Cloud LoadBalancer | native | Real public IP, no tunneling needed |
| VM (GitLab) | Multipass | 1.16 | Lightweight Ubuntu VM on macOS M-series |

---

## Key Technology Decisions

### GKE Autopilot over GKE Standard

| | Autopilot | Standard |
|---|---|---|
| Node management | Google managed | Self-managed |
| Cost | Pay per pod | Pay per node |
| Security | Hardened by default | Manual hardening |
| Setup time | Minutes | Hours |

Autopilot eliminates node pool configuration, OS patching, and capacity planning.
Trade-off: less control over node-level settings (e.g. containerd config not possible).

### Kind over Minikube or K3s

| | Kind | Minikube | K3s |
|---|---|---|---|
| Apple Silicon | via Docker | Docker driver | needs Lima VM |
| Terraform provider | tehcyx/kind ✅ | limited | none |
| No CLI needed | ✅ | ❌ | ❌ |

Kind runs entirely inside Docker. Terraform uses the Kind Go library directly — no `kind` binary required.

### Traefik v3 over ingress-nginx

ingress-nginx was retired March 2026 — no security patches. Traefik v3 is the maintained replacement with native Gateway API support and identical functionality.

### GCP Artifact Registry over GitLab CE Registry for GKE

GKE nodes can't reach the local GitLab CE registry (192.168.2.2) without a tunnel.
Artifact Registry is GCP-native — nodes pull images directly with IAM authentication,
no credentials needed in pods.

### GCS over GitLab CE HTTP backend for GKE state

GCS provides native GCP state storage with built-in locking. GitLab CE HTTP backend
is used for on-prem state (keeps everything local). GKE state uses GCS
(`react-k8s-demo-tfstate` bucket) — production-grade, versioned, no external dependency.

### Permanent SA key over short-lived tokens for CI

GCP access tokens expire in 1 hour — unusable for CI. A dedicated `gke-ci-runner`
service account with `container.developer` + `artifactregistry.writer` roles provides
permanent credentials. The JSON key is stored as a GitLab CI variable (masked, unprotected).

### Shell executor over Kubernetes executor

The GitLab runner runs on the developer Mac with direct access to:
- OrbStack Docker (for Kind cluster operations)
- gcloud CLI (for GKE operations)
- kubectl (configured per pipeline)

A Kubernetes executor would require a separate cluster just for CI — overkill for this task.

---

## Security Decisions

### nginx on port 8080 (non-root)

nginx cannot bind port 80 as non-root. Port 8080 enables:
- `runAsNonRoot: true` + `runAsUser: 101`
- `Drop ALL` Linux capabilities
- `seccompProfile: RuntimeDefault`
- PSA baseline policy compliance

The Service maps `80 → 8080` so external traffic still uses port 80.

### Catch-all Ingress (on-prem only)

`enable_catch_all_ingress=true` accepts any hostname — required for ngrok free tier
where the Host header is the ngrok domain. Acceptable for local demo behind ngrok.
Production fix: real domain + cert-manager + `enable_catch_all_ingress=false`.

### GitLab CE Registry HSTS

GitLab CE enables HSTS on registry responses causing Docker to force HTTPS.
Fix: disable HSTS on registry nginx (`scripts/fix-gitlab-registry-hsts.sh`).
Must re-run after each `gitlab-ctl reconfigure`.

### Deployment vs Terraform ownership

Terraform owns infrastructure (Namespace, SA, Service, Ingress, HPA, PDB).
GitLab CI owns the Deployment — avoids chicken-and-egg: Terraform runs before
any image exists in the registry.

---

## Known Trade-offs vs Production

| Item | This Demo | Production |
|---|---|---|
| GKE HTTPS | HTTP only | GCP Certificate Manager + managed SSL |
| Custom domain | Raw IP / ngrok | Cloud DNS + real domain |
| GitLab registry | HTTP (on-prem) | HTTPS with valid cert |
| GitLab CE | Multipass VM (local) | GCP VM or GitLab SaaS |
| GitLab runner | Shell on Mac | Kubernetes executor |
| On-prem state | GitLab CE HTTP | GCS or S3 + locking |
| Secrets | .envrc + CI vars | HashiCorp Vault |
| Image scanning | None | Trivy in CI |
| GitOps | Push-based kubectl | ArgoCD / FluxCD |
| Multi-region | Single region | GKE regional cluster |
