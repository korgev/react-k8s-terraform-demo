# K8s WebApp — DevOps Task Solution

> **Kubernetes · Terraform · GitLab CI/CD · React · Prometheus/Grafana**

A production-grade demonstration of a full DevOps workflow:  
Terraform provisions a local Kind Kubernetes cluster → GitLab CI/CD builds and deploys a React application → Prometheus + Grafana provide observability.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        Developer Laptop (macOS M-series)     │
│                                                             │
│  ┌──────────────┐    ┌──────────────────────────────────┐  │
│  │  Terraform   │    │   OrbStack (Docker runtime)       │  │
│  │  modules/    │───▶│                                   │  │
│  │  kind-cluster│    │  ┌─────────────────────────────┐ │  │
│  │  k8s-app     │    │  │   Kind Cluster (K8s v1.29)  │ │  │
│  │  monitoring  │    │  │                             │ │  │
│  └──────────────┘    │  │  ┌──────────┐ ┌──────────┐ │ │  │
│                       │  │  │control-  │ │ worker   │ │ │  │
│                       │  │  │plane     │ │ node     │ │ │  │
│                       │  │  │(ingress) │ │          │ │ │  │
│                       │  │  └──────────┘ └──────────┘ │ │  │
│                       │  │                             │ │  │
│                       │  │  Namespaces:                │ │  │
│                       │  │  ├── ingress-nginx          │ │  │
│                       │  │  ├── webapp                 │ │  │
│                       │  │  │   └── react-app (x2)    │ │  │
│                       │  │  └── monitoring             │ │  │
│                       │  │      ├── prometheus         │ │  │
│                       │  │      └── grafana            │ │  │
│                       │  └─────────────────────────────┘ │  │
│                       └──────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
          │ port 80/443              │ port 3000
          ▼                          ▼
    http://webapp.local        http://grafana.local
    (or ngrok public URL)      (or kubectl port-forward)

─────────────────────────────────────────────────────────────
GitLab.com (cloud)
  ├── Repository (source code)
  ├── Container Registry (Docker images)
  └── CI/CD Pipeline
        build:react  ──▶  docker:build-push  ──▶  deploy:k8s
                                                       │
                                              (manual) rollback:k8s
```

---

## Stack

| Layer           | Technology                                    |
|-----------------|-----------------------------------------------|
| App             | React 18 + Vite + Nginx (alpine)              |
| Containerisation| Docker (multi-stage build)                    |
| Orchestration   | Kubernetes 1.29 via Kind                      |
| IaC             | Terraform 1.7+ (modular)                      |
| CI/CD           | GitLab CI/CD (`.gitlab-ci.yml`)               |
| Registry        | GitLab Container Registry (built-in)          |
| Ingress         | Nginx Ingress Controller                      |
| Monitoring      | kube-prometheus-stack (Prometheus + Grafana)  |
| Runtime (macOS) | OrbStack + Docker CLI                         |

---

## Repository Structure

```
react-k8s-terraform-demo/
├── .gitlab-ci.yml              # CI/CD pipeline (build → push → deploy → rollback)
├── .gitignore
│
├── app/                        # React application
│   ├── src/
│   │   ├── App.jsx             # Main component — deployment dashboard
│   │   ├── App.css             # Styles
│   │   └── main.jsx            # Entry point
│   ├── index.html
│   ├── vite.config.js
│   ├── package.json
│   ├── Dockerfile              # Multi-stage: node builder + nginx server
│   ├── nginx.conf              # Hardened nginx config + security headers
│   └── .dockerignore
│
├── terraform/
│   ├── main.tf                 # Root — orchestrates all modules
│   ├── monitoring.tf           # Monitoring module wiring
│   ├── variables.tf            # Input variables
│   ├── sensitive-vars.tf       # Sensitive variable declarations
│   ├── outputs.tf              # Output values
│   ├── versions.tf             # Provider version pinning
│   ├── terraform.tfvars.example
│   └── modules/
│       ├── kind-cluster/       # Provisions Kind K8s cluster
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       ├── k8s-app/            # Deploys app to K8s
│       │   ├── main.tf         # Deployment, Service, Ingress, HPA, PDB
│       │   ├── variables.tf
│       │   └── outputs.tf
│       └── monitoring/         # Prometheus + Grafana
│           ├── main.tf
│           └── variables.tf
│
└── docs/
    ├── README.md               # ← You are here
    ├── SETUP.md                # Step-by-step setup guide (start here)
    ├── SECURITY.md             # Security decisions + reviewer access
    ├── ARCHITECTURE.md         # Deep-dive architecture + decisions
    └── RUNBOOK.md              # Day-2 operations + troubleshooting
```

---

## Quick Start

Full step-by-step instructions are in **[SETUP.md](docs/SETUP.md)**.

```bash
# 1. Clone the repo
git clone https://gitlab.com/YOUR_USERNAME/react-k8s-terraform-demo.git
cd react-k8s-terraform-demo

# 2. Install prerequisites (macOS — see SETUP.md for full detail)
brew install git orbstack kubectl helm

# 3. Provision the cluster
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your registry path
terraform init && terraform apply

# 4. Add local DNS entry
echo "127.0.0.1 webapp.local grafana.local" | sudo tee -a /etc/hosts

# 5. Open the app
open http://webapp.local
```

---

## CI/CD Pipeline Flow

```
git push → main
    │
    ├─[build:react]──────── npm ci + vite build → dist/ artifact
    │
    ├─[docker:build-push]── docker build (multi-stage) → push to GitLab registry
    │                        tags: :$SHA + :latest
    │
    ├─[deploy:kubernetes]── kubectl set image → rollout status (auto-rollback on failure)
    │                        annotates deployment with pipeline metadata
    │
    └─[rollback:kubernetes] ← MANUAL — click "Run" in GitLab UI to revert
```

---

## Accessing Services

| Service   | URL                        | Notes                                  |
|-----------|----------------------------|----------------------------------------|
| React App | http://webapp.local        | After /etc/hosts entry                 |
| Grafana   | http://grafana.local       | admin / see SETUP.md                   |
| Prometheus| kubectl port-forward only  | `kubectl port-forward svc/... 9090:9090` |
| Public URL| ngrok (see SETUP.md)       | For external reviewer access           |

---

## Monitoring

Grafana dashboards available at `http://grafana.local`:
- **Kubernetes / Compute Resources / Namespace** — pod CPU/memory
- **Kubernetes / Networking** — ingress traffic
- **Node Exporter Full** — host-level metrics

---

## Security Highlights

See [SECURITY.md](docs/SECURITY.md) for the full security posture.

- ✅ Least-privilege RBAC + dedicated ServiceAccount
- ✅ No secrets in code (all via GitLab CI/CD variables)
- ✅ Registry access via scoped deploy tokens (not personal tokens)
- ✅ Multi-stage Docker build — no build tools in production image
- ✅ Nginx security headers (X-Frame-Options, CSP, etc.)
- ✅ Pod Security Admission (baseline policy enforced)
- ✅ kubeconfig at 0600 permissions, never committed to git
- ✅ Auto-rollback on failed deployment

---

*Built as a DevOps assessment task — Terraform + Kind + GitLab CI/CD + React + Prometheus/Grafana*

---

## Architecture Diagram

See `docs/architecture.svg` for the full visual — opens in any browser:

```bash
open docs/architecture.svg
```

