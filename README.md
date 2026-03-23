# react-k8s-terraform-demo

> **Kubernetes · Terraform · GitLab CI/CD · React · Prometheus/Grafana**

A DevOps assessment task solution that provisions Kubernetes with Terraform, deploys a React application through GitLab CI/CD, and exposes it publicly.

This repository contains **two deployment targets**:

- **Primary implementation:** local/on-prem Kubernetes using **Kind**
- **Cloud extension:** managed Kubernetes on **GKE**

> **Note:** This is a read-only GitHub mirror of the project.
> The CI/CD pipeline runs on a self-hosted GitLab CE instance.
> Live app: https://mervin-tetrahydric-dwayne.ngrok-free.dev

## Live Access

| Resource | Local / On-prem | GKE / Cloud |
|---|---|---|
| React App (public) | https://mervin-tetrahydric-dwayne.ngrok-free.dev | https://acba.harmar.site |
| Grafana | http://grafana.local | https://grafana.harmar.site |
| GitLab CE | http://192.168.2.2 | Self-hosted CI/CD control plane |
| Source code (GitHub mirror) | https://github.com/korgev/react-k8s-terraform-demo | https://github.com/korgev/react-k8s-terraform-demo |

---

---

## Architecture Overview
```
┌──────────────────────────────────────────────────────────────────┐
│                  Developer Laptop (macOS Apple Silicon)          │
│                                                                  │
│  ┌─────────────────┐    ┌──────────────────────────────────────┐ │
│  │   Terraform     │    │      OrbStack (Docker runtime)       │ │
│  │   modules/      │───▶│                                      │ │
│  │   kind-cluster  │    │  ┌────────────────────────────────┐  │ │
│  │   k8s-app       │    │  │   Kind Cluster (K8s v1.32)     │  │ │
│  │   monitoring    │    │  │                                │  │ │
│  └─────────────────┘    │  │  ┌─────────────┐ ┌──────────┐ │  │ │
│                          │  │  │control-plane│ │  worker  │ │  │ │
│  ┌─────────────────┐    │  │  └─────────────┘ └──────────┘ │  │ │
│  │  direnv .envrc  │    │  │                                │  │ │
│  │  (secrets only) │    │  │  Namespaces:                   │  │ │
│  └─────────────────┘    │  │  ├── traefik   (Traefik v3)   │  │ │
│                          │  │  ├── webapp    (react-app ×2) │  │ │
│                          │  │  └── monitoring               │  │ │
│                          │  │      ├── prometheus           │  │ │
│                          │  │      └── grafana              │  │ │
│                          │  └────────────────────────────────┘  │ │
│                          └──────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
         │ hostPort 80                        │ hostPort 80
         ▼                                    ▼
   http://webapp.local               http://grafana.local
         │
         ▼
   ngrok launchd service (permanent, auto-start on login)
         │
         ▼
   https://mervin-tetrahydric-dwayne.ngrok-free.dev  (public HTTPS)

────────────────────────────────────────────────────────────────────
Multipass VM (192.168.2.2) — Ubuntu 24.04 — 4GB RAM + 4GB swap
  ├── GitLab CE 18.10
  │   ├── Git repository
  │   ├── Container Registry (:5050 HTTP)
  │   ├── CI/CD pipelines
  │   └── Terraform HTTP backend (remote state + locking)
  └── GitLab Runner (shell executor on host Mac)

CI/CD Pipeline (triggered on push to main):
  test:build ──▶ docker:build-push ──▶ deploy:kubernetes
                                              │
                                     (manual) rollback:kubernetes
```

---

## Stack

| Layer            | Technology                                           |
|------------------|------------------------------------------------------|
| App              | React 18 + Vite + nginx:alpine (port 8080)           |
| Containerisation | Docker multi-stage build (~44MB image)               |
| Orchestration    | Kubernetes 1.32 via Kind (tehcyx/kind provider)      |
| IaC              | Terraform 1.7+ — 3 reusable modules                  |
| CI/CD            | GitLab CI/CD — shell executor on macOS               |
| Registry         | GitLab CE Container Registry (self-hosted :5050)     |
| Ingress          | Traefik v3 (replaced ingress-nginx, EOL Mar 2026)    |
| Monitoring       | kube-prometheus-stack (Prometheus + Grafana)          |
| TF State         | GitLab CE HTTP backend with locking                  |
| GitLab CE        | Self-hosted on Multipass VM (Ubuntu 24.04)           |
| Runtime (macOS)  | OrbStack + Docker CLI                                |
| Secrets          | direnv (.envrc gitignored) + GitLab CI masked vars   |
| Public access    | ngrok static domain (launchd permanent service)      |

---

## Repository Structure
```
react-k8s-terraform-demo/
├── .gitlab-ci.yml              # CI/CD pipeline (4 stages)
├── .gitignore
├── Makefile                    # Convenience targets (tf-init, tf-apply, etc.)
│
├── app/                        # React application
│   ├── src/
│   │   ├── App.jsx             # Deployment dashboard — shows live build metadata
│   │   ├── App.css
│   │   └── main.jsx
│   ├── Dockerfile              # Multi-stage: node builder + nginx:alpine
│   ├── nginx.conf              # Hardened config + security headers
│   ├── vite.config.js
│   └── package.json
│
├── kubernetes/
│   └── deployment.yaml         # Deployment manifest (managed by CI/CD)
│
├── terraform/
│   ├── main.tf                 # Root — orchestrates all modules
│   ├── monitoring.tf           # Monitoring module wiring
│   ├── variables.tf            # Input variables
│   ├── sensitive-vars.tf       # Sensitive variable declarations
│   ├── outputs.tf              # Output values + next_steps guide
│   ├── versions.tf             # Provider pinning + HTTP backend block
│   ├── backend.hcl.example     # Backend config template (gitignored when filled)
│   ├── terraform.tfvars.example
│   └── modules/
│       ├── kind-cluster/       # Provisions Kind cluster + containerd registry config
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       ├── k8s-app/            # Namespace, SA, pull secret, Service, Ingress, HPA, PDB
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       └── monitoring/         # kube-prometheus-stack (Prometheus + Grafana)
│           ├── main.tf
│           ├── variables.tf
│           └── outputs.tf
│
├── scripts/
│   ├── validate.sh             # Pre-flight + post-deploy validation
│   ├── fix-gitlab-registry-hsts.sh  # Fix GitLab CE HSTS after reconfigure
│   └── envrc.template          # Template for .envrc
│
└── docs/
    ├── SETUP.md                # Step-by-step setup guide (start here)
    ├── SECURITY.md             # Security decisions + threat model
    ├── ARCHITECTURE.md         # Deep-dive architecture + decisions
    ├── WORKFLOW.md             # Pipeline + Terraform flow diagrams
    ├── REVIEWER.md             # Evidence mapping for each task requirement
    └── architecture.pdf        # Visual architecture diagram (2 pages)
```

---

## Quick Start

Full step-by-step instructions are in **[docs/SETUP.md](docs/SETUP.md)**.

---

## CI/CD Pipeline
```
git push → main
    │
    ├─[test:build]──────────── npm ci + eslint (lint only — Docker builds the app)
    │
    ├─[docker:build-push]───── docker build (multi-stage, VITE_* vars injected)
    │                           push :$CI_COMMIT_SHORT_SHA + :v1.0.$CI_PIPELINE_IID
    │
    ├─[deploy:kubernetes]────── envsubst → kubectl apply
    │                           rollout status --timeout=180s
    │                           auto-rollback on failure
    │
    └─[rollback:kubernetes]──── MANUAL — click Run in GitLab UI
                                kubectl rollout undo
```

---


## Monitoring

Grafana at `http://grafana.local` — pre-loaded dashboards:

- **Kubernetes / Compute Resources / Namespace** — pod CPU + memory
- **Kubernetes / Networking** — ingress traffic
- **Node Exporter Full** — host-level metrics

---

## Security Highlights

See [docs/SECURITY.md](docs/SECURITY.md) for the full threat model.

---

## Validation
```bash
bash scripts/validate.sh
# ✅ ALL CHECKS PASSED — ready to share!
```

---


---

*DevOps assessment task — Terraform + Kind + GitLab CI/CD + React + Prometheus/Grafana*
