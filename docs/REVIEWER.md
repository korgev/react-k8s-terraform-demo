# REVIEWER.md — Task Compliance Evidence

This document maps each task requirement to its implementation.

---

## Live URLs

| Resource | URL |
|---|---|
| Running app (public) | https://mervin-tetrahydric-dwayne.ngrok-free.dev |
| Source code (GitHub) | https://github.com/korgev/react-k8s-terraform-demo |
| Local app | http://webapp.local |
| Grafana | http://grafana.local (admin / see SETUP.md) |

---

## Requirement 1 — Terraform provisions Kubernetes cluster

| Evidence | Location |
|---|---|
| Terraform modules | `terraform/modules/kind-cluster/` |
| Kind cluster config | `terraform/modules/kind-cluster/main.tf` |
| K8s version pinned | `v1.32.0` in `terraform/variables.tf` |
| kubeconfig generated | `terraform/modules/kind-cluster/main.tf` → `local_file.kubeconfig` |
| Remote state backend | `terraform/versions.tf` → `backend "http" {}` |
| Backend config template | `terraform/backend.hcl.example` |
| No kind CLI needed | `tehcyx/kind` provider handles everything via Docker |
````bash
# Verify cluster is running
kubectl get nodes
# react-k8s-cluster-control-plane   Ready   control-plane
# react-k8s-cluster-worker           Ready   <none>
````

---

## Requirement 2 — GitLab CE + React app + CI/CD pipeline

| Evidence | Location |
|---|---|
| Pipeline definition | `.gitlab-ci.yml` |
| React application | `app/src/App.jsx` |
| Dockerfile | `app/Dockerfile` (multi-stage) |
| 4 pipeline stages | `test:build` → `docker:build-push` → `deploy:kubernetes` → `rollback:kubernetes` |
| Build stage | npm ci + eslint lint validation |
| Docker stage | Multi-stage build, VITE_* vars injected, :SHA + :v1.0.IID tags |
| Deploy stage | envsubst + kubectl apply + rollout status + auto-rollback |
| Rollback stage | Manual trigger, kubectl rollout undo, environment: rollback |
````bash
# Verify pipeline ran successfully
# GitLab → CI/CD → Pipelines → all stages green

# Verify pods running
kubectl get pods -n webapp
# react-app-xxx   2/2   Running
````

---

## Requirement 3 — Application exposed via public URL

| Evidence | Location |
|---|---|
| Traefik v3 Ingress | `terraform/main.tf` → `helm_release.traefik` |
| Ingress resource | `terraform/modules/k8s-app/main.tf` → `kubernetes_ingress_v1` |
| ngrok launchd service | `~/Library/LaunchAgents/com.ngrok.react-k8s.plist` |
| Static domain | `mervin-tetrahydric-dwayne.ngrok-free.dev` (permanent) |
| Public URL | https://mervin-tetrahydric-dwayne.ngrok-free.dev |
````bash
# Verify ingress
kubectl get ingress -n webapp

# Verify public URL
curl -sI https://mervin-tetrahydric-dwayne.ngrok-free.dev | head -3
# HTTP/2 200
````

---

## Bonus 1 — Prometheus + Grafana monitoring

| Evidence | Location |
|---|---|
| Monitoring module | `terraform/modules/monitoring/main.tf` |
| kube-prometheus-stack | v72.6.2 — Prometheus + Grafana + Alertmanager |
| Grafana Ingress | `terraform/modules/monitoring/main.tf` → `kubernetes_ingress_v1` |
| Grafana URL | http://grafana.local |
````bash
# Verify monitoring stack
kubectl get pods -n monitoring
# prometheus-xxx   2/2   Running
# grafana-xxx      1/1   Running
# alertmanager-xxx 2/2   Running

# Open Grafana
open http://grafana.local
# Login: admin / (your TF_VAR_grafana_admin_password)
# Dashboards: Kubernetes / Compute Resources / Namespace
````

---

## Bonus 2 — Rollback capability

| Evidence | Location |
|---|---|
| Auto-rollback | `.gitlab-ci.yml` → `deploy:kubernetes` stage |
| Manual rollback job | `.gitlab-ci.yml` → `rollback:kubernetes` stage |
| Rollback mechanism | `kubectl rollout undo` |
| Environment action | `environment.action: rollback` |

Auto-rollback trigger:
````yaml
kubectl rollout status deployment/react-app -n webapp --timeout=180s \
  || (kubectl rollout undo deployment/react-app -n webapp && exit 1)
````

Manual rollback: GitLab → CI/CD → Pipelines → click ▶ on `rollback:kubernetes`

---

## Bonus 3 — Terraform modules

| Module | Responsibility | Variables | Outputs |
|---|---|---|---|
| `kind-cluster` | Cluster, kubeconfig, containerd config | cluster_name, kubernetes_version, registry_host | kubeconfig_path, cluster_name, endpoint |
| `k8s-app` | Namespace, SA, pull secret, Service, Ingress, HPA, PDB | app_name, namespace, registry_host, enable_catch_all_ingress | namespace, service_name, pull_secret_name |
| `monitoring` | kube-prometheus-stack, Grafana Ingress | grafana_admin_password, grafana_host | grafana_url, port_forward_cmd |

---

## Validation Script
````bash
bash scripts/validate.sh

# Expected output:
# ✅ ALL CHECKS PASSED — ready to share!
````

---

## Stack Summary

| Layer | Technology | Version |
|---|---|---|
| App | React 18 + Vite + nginx | 18.x / 5.x / 1.25 |
| Container | Docker multi-stage | 28.x |
| Orchestration | Kubernetes via Kind | 1.32 |
| IaC | Terraform | 1.7+ |
| CI/CD | GitLab CE | 18.10 |
| Registry | GitLab CE Container Registry | :5050 |
| Ingress | Traefik v3 | 3.6.9 |
| Monitoring | kube-prometheus-stack | 72.6.2 |
| Public access | ngrok static domain | 3.x |
