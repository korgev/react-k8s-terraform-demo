# ARCHITECTURE.md — Design Decisions & Technical Deep Dive

## Stack Overview

| Layer | Technology | Version | Why Chosen |
|---|---|---|---|
| App | React 18 + Vite | 18.2 / 5.x | Fast builds, small bundles, modern tooling |
| Container | Docker multi-stage | 28.x | node builder → nginx server, minimal attack surface |
| Web server | nginx (alpine) | 1.25 | Lightweight, production-grade static file serving |
| Orchestration | Kubernetes (Kind) | 1.32 | Local K8s without cloud costs, Docker-native |
| IaC | Terraform | 1.7+ | Industry standard, modular, state management |
| CI/CD | GitLab CE | 18.10 | Self-hosted (task requirement), full GitLab feature set |
| Ingress | Traefik v3 | 3.6.9 | Replaced ingress-nginx (retired March 2026) |
| Monitoring | kube-prometheus-stack | 72.x | Prometheus + Grafana + Alertmanager bundled |
| Runtime (macOS) | OrbStack | latest | Lighter than Docker Desktop on Apple Silicon |
| Tunnel | ngrok (launchd) | 3.x | Permanent HTTPS URL, runs as background service |
| VM (GitLab) | Multipass | 1.16 | Lightweight Ubuntu VM on macOS M-series |

## Why These Technology Choices

### Kind over Minikube or K3s

| | Kind | Minikube | K3s |
|---|---|---|---|
| macOS Apple Silicon | via Docker | Docker driver | needs Lima VM |
| Terraform provider | tehcyx/kind | limited | none |
| Reviewer reproducibility | Docker only | driver-dependent | Linux-first |

Kind runs entirely inside Docker. No CLI needed — Terraform uses the Kind Go library directly.

### Traefik v3 over ingress-nginx

ingress-nginx was retired March 2026 — no further security patches.
Traefik v3 is the maintained replacement with identical functionality and native Gateway API support.

### OrbStack over Docker Desktop

OrbStack uses 50-70% less RAM on Apple Silicon. Critical when running Kind + GitLab CE VM simultaneously on 16GB RAM.

### ngrok launchd service over terminal session

Running ngrok as a macOS launchd service means:
- Starts automatically on login
- Runs in background — no terminal needed
- Static domain — URL never changes between restarts
- Reviewer can access the app anytime, not just when a terminal is open

## Security Decisions

### nginx on port 8080 (non-root)

nginx cannot bind port 80 as non-root. Port 8080 enables:
- runAsNonRoot: true
- Drop ALL capabilities
- seccompProfile: RuntimeDefault
- Satisfies PSA restricted at pod level

The Service maps 80 → 8080, so external traffic still uses port 80.

### Catch-all Ingress

Trade-off: enable_catch_all_ingress=true accepts any hostname.
Required for ngrok free tier (URL is stable but host header is the ngrok domain).
Acceptable for local demo — cluster is behind ngrok, not directly internet-exposed.
Production fix: stable domain + cert-manager + enable_catch_all_ingress=false.

### GitLab CE Registry HSTS

GitLab CE sends Strict-Transport-Security on registry responses causing Docker to
force HTTPS on subsequent logins. Fix: disable HSTS on registry nginx only.
scripts/fix-gitlab-registry-hsts.sh must be re-run after each gitlab-ctl reconfigure.

## Known Trade-offs vs Production

| Item | This Demo | Production |
|---|---|---|
| Ingress host | catch-all | Specific domain |
| TLS | ngrok only | cert-manager + Let's Encrypt |
| GitLab registry | HTTP local | HTTPS with valid cert |
| K8s cluster | Kind local | EKS/GKE/AKS |
| GitLab runners | Shell on Mac | Kubernetes executor |
| State backend | GitLab CE HTTP | S3 + DynamoDB lock |
| Secrets | .envrc + CI vars | HashiCorp Vault |
| Image scanning | None | Trivy in CI |
| GitOps | Push-based kubectl | ArgoCD/FluxCD |
