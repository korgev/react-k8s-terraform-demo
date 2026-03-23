# REVIEWER.md — Task Compliance Evidence

This document maps each task requirement to its implementation.
The project has **two deployments**: on-prem (Kind) and cloud (GKE).

---

## Live URLs

| Resource | URL |
|---|---|
| **On-prem app (public)** | https://mervin-tetrahydric-dwayne.ngrok-free.dev |
| **GKE app (public)** | https://acba.harmar.site |
| **Grafana (GKE)** | https://grafana.harmar.site |
| **Source code (GitHub)** | https://github.com/korgev/react-k8s-terraform-demo |

> **Note:** This is a read-only GitHub mirror of the project.
> The CI/CD pipeline runs on a self-hosted GitLab CE instance.
> 
---

## Requirement 1 — Terraform provisions Kubernetes cluster

| Evidence | On-prem | GKE |
|---|---|---|
| Terraform module | `modules/kind-cluster/` | `modules/gke-cluster/` |
| Cluster type | Kind v1.32 (local) | GKE Autopilot (GCP) |
| kubeconfig generated | ✅ `local_file.kubeconfig` | ✅ `local_file.kubeconfig` |
| Remote state | GitLab CE HTTP backend | GCS bucket |
| Provider | `tehcyx/kind` | `hashicorp/google` |
```bash
# Verify on-prem
kubectl get nodes --kubeconfig kubeconfig

# Verify GKE
gcloud container clusters list --project react-k8s-demo
```

---

## Requirement 2 — GitLab CE + React app + CI/CD pipeline

| Evidence | Location |
|---|---|
| Pipeline definition | `.gitlab-ci.yml` |
| React application | `app/src/App.jsx` |
| Dockerfile | `app/Dockerfile` (multi-stage, non-root) |
| On-prem stages | `test:build` → `docker:build-push` → `deploy:kubernetes` → `rollback:kubernetes` |
| GKE stages | `test:build` → `docker:build-push-gcp` → `deploy:kubernetes-gcp` → `rollback:kubernetes-gcp` |
| Branch isolation | `main` → on-prem, `feature/gke` → GKE |

---

## Requirement 3 — Application exposed via public URL

| | On-prem | GKE |
|---|---|---|
| Method | Traefik v3 + ngrok static domain | GCP Cloud LoadBalancer |
| URL | https://mervin-tetrahydric-dwayne.ngrok-free.dev | http://35.226.47.178 |
| HTTPS | ✅ via ngrok | HTTP (HTTPS = production next step) |
| Permanent | ✅ launchd service | ✅ GKE native LB |

---

## Bonus 1 — Monitoring

| | On-prem | GKE |
|---|---|---|
| Stack | kube-prometheus-stack v72.6.2 | Grafana + GCP Cloud Monitoring |
| Prometheus | ✅ running | GKE Autopilot built-in metrics |
| Grafana | http://grafana.local | https://grafana.harmar.site |

---

## Bonus 2 — Rollback capability

| Evidence | On-prem | GKE |
|---|---|---|
| Auto-rollback | `kubectl rollout undo` on timeout | ✅ same |
| Manual rollback | `rollback:kubernetes` job | `rollback:kubernetes-gcp` job |

---

## Bonus 3 — Terraform modules

| Module | Responsibility |
|---|---|
| `kind-cluster` | Kind cluster + kubeconfig + containerd registry config |
| `gke-cluster` | VPC + subnet + firewall + GKE Autopilot + node SA |
| `k8s-app` | Namespace + SA + pull secret + Service + Ingress + HPA + PDB |
| `monitoring` | kube-prometheus-stack (on-prem) / Grafana (GKE) |

---

## Production Improvements (next steps)

- **HTTPS on GKE** — GCP Certificate Manager + managed SSL cert
- **Custom domain** — Cloud DNS + real domain 
- **GitOps** — ArgoCD/FluxCD replacing push-based kubectl
- **Image scanning** — Trivy in CI pipeline
- **Vault** — HashiCorp Vault replacing .envrc secrets
- **Multi-region** — GKE regional cluster for HA

---

## Validation
```bash
# On-prem
bash scripts/validate.sh

# GKE
kubectl get pods -n webapp --kubeconfig kubeconfig-gke-ci
curl -sI https://acba.harmar.site
```
