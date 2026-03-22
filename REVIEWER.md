# REVIEWER.md — Evaluation Guide

> Time to review: ~15 minutes.

## Live Access

| Resource | URL | Credentials |
|---|---|---|
| React App (public) | https://mervin-tetrahydric-dwayne.ngrok-free.dev | None |
| GitLab CE | http://192.168.2.2/rwx/react-k8s-terraform-demo | Guest (provided separately) |
| Grafana | http://grafana.local (requires /etc/hosts) | Provided separately |

## Task Requirements — Evidence

### 1. Provisioning with Terraform
- Kind cluster: `terraform/modules/kind-cluster/main.tf`
- kubeconfig generated at 0600: `module.kind_cluster.local_file.kubeconfig`
- 3 reusable modules: kind-cluster, k8s-app, monitoring

### 2. Application Deployment
- GitLab CE 18.10 on Multipass VM (192.168.2.2)
- React 18 + Vite app, 2 pods running in `webapp` namespace
- Pipeline: `.gitlab-ci.yml` — 4 stages (test → docker → deploy → rollback)
- Build: npm ci + eslint + vite build
- Docker: multi-stage build → push to GitLab Container Registry
- Deploy: envsubst + kubectl apply with auto-rollback on failure

### 3. Accessibility
- Traefik v3 Ingress (replaced ingress-nginx — retired March 2026)
- Public URL: https://mervin-tetrahydric-dwayne.ngrok-free.dev
- Runs as macOS launchd service — permanent, no terminal needed

### Bonus
- Monitoring: kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
- Rollback: automatic on failure + manual `rollback:kubernetes` job in pipeline
- Terraform modules: 3 modules with clean input/output contracts

## Documentation
- `docs/ARCHITECTURE.md` — every technology choice with rationale
- `docs/SETUP.md` — complete zero-to-running guide
- `docs/SECURITY.md` — threat model + trade-offs
- `docs/WORKFLOW.md` — pipeline + Terraform flow diagrams
