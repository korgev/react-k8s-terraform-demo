# react-k8s-terraform-demo

> **Kubernetes · Terraform · GitLab CI/CD · React · Prometheus/Grafana**  
> Full DevOps pipeline: provision → build → push → deploy → monitor → rollback

## Quick Navigation

| Document | Purpose |
|----------|---------|
| [docs/README.md](docs/README.md) | Project overview + architecture diagram |
| [docs/SETUP.md](docs/SETUP.md) | **Start here** — zero to running in 30 minutes |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Design decisions + technical deep-dive |
| [docs/SECURITY.md](docs/SECURITY.md) | Security posture + reviewer access guide |
| [docs/RUNBOOK.md](docs/RUNBOOK.md) | Day-2 operations + troubleshooting |

## Stack

```
React 18 (Vite) → Dockerfile (multi-stage) → GitLab CI/CD
→ GitLab Container Registry → kubectl → Kind (K8s 1.29)
→ Nginx Ingress → Prometheus + Grafana
All infrastructure: Terraform (modular)
```

## Task Completion Checklist

- [x] Terraform provisions Kind K8s cluster (modular structure)
- [x] kubeconfig generated and available for CI/CD
- [x] React app with production Dockerfile + Nginx
- [x] GitLab CI/CD pipeline: build → push → deploy → rollback
- [x] App exposed via Nginx Ingress (`http://webapp.local`)
- [x] Public URL via ngrok for reviewer
- [x] Prometheus + Grafana monitoring (bonus)
- [x] Pipeline rollback capability (bonus)
- [x] Terraform modules structure (bonus)
- [x] Full documentation suite (README, SETUP, ARCHITECTURE, SECURITY, RUNBOOK)
# react-k8s-terraform-demo


