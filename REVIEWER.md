# REVIEWER.md — Evaluation Guide

> This document tells you exactly what to look at to verify each requirement.  
> Time to review: ~15 minutes with the checklist below.

---

## Access You Have Been Granted

| Resource | Access | Credentials |
|----------|--------|-------------|
| GitLab project | Guest (read-only) | Via project URL shared with you |
| Running application | Public URL | ngrok URL shared with you |
| Grafana dashboards | Read-only viewer | URL + credentials shared with you |

You cannot push code, modify pipelines, or access any credentials.  
All access expires 7 days from the date it was shared.

---

## Requirement Verification Checklist

### ✅ 1. Kubernetes Cluster — Provisioned with Terraform

**Where to look:** `terraform/` directory

```
terraform/
├── versions.tf          ← provider version pinning (tehcyx/kind ~> 0.4)
├── main.tf              ← root orchestration
├── modules/
│   ├── kind-cluster/    ← provisions the Kind cluster (Terraform module)
│   ├── k8s-app/         ← namespace, service, ingress, HPA, PDB
│   └── monitoring/      ← Prometheus + Grafana via Helm
```

**Evidence of modular structure:** 3 independent modules with clear input/output contracts.

**kubeconfig generation:** `terraform/modules/kind-cluster/main.tf` line ~60:
```hcl
resource "local_file" "kubeconfig" {
  content         = kind_cluster.this.kubeconfig
  filename        = var.kubeconfig_path
  file_permission = "0600"
}
```

---

### ✅ 2. GitLab CI/CD Pipeline

**Where to look:** `.gitlab-ci.yml` (root of repo)

**Stages:**

| Stage | Job | What it does |
|-------|-----|-------------|
| `build` | `build:react` | `npm ci` + `vite build` → produces `dist/` artifact |
| `docker` | `docker:build-push` | Multi-stage Docker build → pushes to GitLab Container Registry |
| `deploy` | `deploy:kubernetes` | `envsubst` + `kubectl apply` → deploys to K8s, waits for rollout |
| `rollback` | `rollback:kubernetes` | Manual trigger → `kubectl rollout undo` |

**Pipeline runs:** GitLab → CI/CD → Pipelines → click any green ✅ pipeline to see logs.

**Container Registry:** GitLab → Packages & Registries → Container Registry → `react-app`  
Each image is tagged with the git commit SHA (immutable + traceable).

---

### ✅ 3. React Application

**Where to look:** `app/` directory

- `app/src/App.jsx` — live deployment dashboard showing cluster status, build metadata, uptime counter
- `app/Dockerfile` — multi-stage build: `node:20-alpine` builder → `nginx:1.25-alpine` server
- `app/nginx.conf` — hardened nginx config with security headers

**Running application:** open the ngrok URL shared with you.  
The UI shows the deployed version, git SHA, environment, and all service statuses.

---

### ✅ 4. Public Accessibility

**Where to look:** `kubernetes/deployment.yaml` + `terraform/modules/k8s-app/main.tf`

Traffic flow:
```
ngrok HTTPS → localhost:80
    → nginx-ingress-controller (NodePort on Kind)
    → Ingress rule (host: webapp.local)
    → Service/react-app (ClusterIP:80)
    → Pod (nginx serving React SPA)
```

Ingress resource: `terraform/modules/k8s-app/main.tf` — `kubernetes_ingress_v1`

---

### ✅ BONUS — Monitoring (Prometheus + Grafana)

**Where to look:** `terraform/modules/monitoring/main.tf`

- Deploys `kube-prometheus-stack` (Prometheus Operator + Grafana + node-exporter + kube-state-metrics)
- Pre-built dashboards: Kubernetes cluster, node, namespace, ingress metrics
- Grafana accessible at the Grafana URL shared with you

**Dashboards to check:**
1. `Kubernetes / Compute Resources / Namespace (Pods)` → pod CPU/memory for `webapp`
2. `NGINX Ingress controller` → HTTP request rate and error rate
3. `Node Exporter Full` → host metrics

---

### ✅ BONUS — Rollback Capability

**Where to look:** `.gitlab-ci.yml` — stage `rollback`, job `rollback:kubernetes`

Two rollback mechanisms:

**1. Automatic** (in `deploy:kubernetes` job):
```bash
if ! kubectl rollout status ... --timeout=180s; then
  kubectl rollout undo deployment/react-app -n webapp
  exit 1
fi
```
Triggers if new pods fail health checks within 3 minutes.

**2. Manual** (visible in GitLab UI):
GitLab → CI/CD → Pipelines → any pipeline → `rollback:kubernetes` → click ▶ Run.

---

### ✅ BONUS — Terraform Modules

**Where to look:** `terraform/modules/`

```
modules/
├── kind-cluster/    variables.tf + main.tf + outputs.tf
├── k8s-app/         variables.tf + main.tf + outputs.tf
└── monitoring/      variables.tf + main.tf + outputs.tf
```

Each module has:
- Clear input `variable` declarations with types and descriptions
- `output` values for cross-module referencing
- Single responsibility (cluster vs app vs monitoring)

---

## Security Highlights (for Senior Reviewers)

| Practice | Implementation | File |
|----------|---------------|------|
| No secrets in code | All via `TF_VAR_*` env + GitLab CI masked variables | `docs/SECURITY.md` |
| Least-privilege registry | Deploy token: `read_registry` scope only | `docs/SECURITY.md` |
| Immutable image tags | Every image tagged with git SHA | `.gitlab-ci.yml` |
| No Deployment in Terraform | Avoids chicken-and-egg; CI owns images | `docs/ARCHITECTURE.md` |
| Pod Security Admission | `enforce: baseline` on webapp namespace | `terraform/modules/k8s-app/main.tf` |
| Auto-rollback on failure | 3-minute timeout then `kubectl rollout undo` | `.gitlab-ci.yml` |
| kubeconfig permissions | Written at `0600` by Terraform | `terraform/modules/kind-cluster/main.tf` |
| Nginx security headers | X-Frame-Options, nosniff, Referrer-Policy | `app/nginx.conf` |

Full security posture: `docs/SECURITY.md`

---

## Documentation Index

| File | Contents |
|------|---------|
| `docs/README.md` | Architecture diagram + stack overview |
| `docs/SETUP.md` | Zero-to-running guide (30 min) |
| `docs/ARCHITECTURE.md` | Every design decision with rationale |
| `docs/SECURITY.md` | Threat model + security decisions |
| `docs/RUNBOOK.md` | Day-2 ops + troubleshooting |
| `REVIEWER.md` | ← You are here |

---

*Questions? Reach out via the GitLab project issue tracker.*
