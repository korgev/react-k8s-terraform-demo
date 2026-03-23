# WORKFLOW.md — How the Solution Works

## Full Pipeline Flow
```
Developer (macOS M-series)
    │
    ├── git push origin main
    │         │
    │         ▼
    │   GitLab CE (192.168.2.2)
    │         │
    │   ┌─────────────────────────────────┐
    │   │ Pipeline Stages                 │
    │   │                                 │
    │   │ 1. test:build                   │
    │   │    npm ci + eslint (lint only)  │
    │   │         ↓                       │
    │   │ 2. docker:build-push            │
    │   │    docker build + push :SHA     │
    │   │         ↓                       │
    │   │ 3. deploy:kubernetes            │
    │   │    envsubst + kubectl apply     │
    │   │    rollout status + auto-undo   │
    │   │         ↓                       │
    │   │ 4. rollback (manual)            │
    │   │    kubectl rollout undo         │
    │   └─────────────────────────────────┘
    │         │
    │         ▼ kubectl apply
    │
    │   Kind Cluster (OrbStack Docker, K8s 1.32)
    │   ├── traefik ns  → Traefik v3 (port 80/443 → host)
    │   ├── webapp ns   → react-app pods (nginx:8080)
    │   │                 Service, Ingress, HPA, PDB
    │   └── monitoring  → Prometheus + Grafana + Alertmanager
    │         │
    │         ▼ port 80
    │
    │   ngrok launchd service (background, auto-start)
    │         │
    │         ▼
    │   https://mervin-tetrahydric-dwayne.ngrok-free.dev
    │         │
    │         ▼
    │   Reviewer browser (anywhere)
```

## Terraform Infrastructure Flow
```
terraform apply
    │
    ├─[1] module.kind_cluster
    │       ├── kind_cluster.this         → 2-node K8s cluster
    │       ├── local_file.kubeconfig     → ./kubeconfig (0600)
    │       └── null_resource.registry   → containerd hosts.toml
    │
    ├─[2] helm_release.traefik            → Traefik v3 ingress
    │
    ├─[3] module.k8s_app
    │       ├── kubernetes_namespace      → webapp + PSA labels
    │       ├── kubernetes_service_account → dedicated SA
    │       ├── kubernetes_secret         → registry pull secret
    │       ├── kubernetes_service        → ClusterIP 80→8080
    │       ├── kubernetes_ingress_v1     → catch-all rule
    │       ├── kubernetes_hpa            → CPU 70%, 2-6 replicas
    │       └── kubernetes_pdb            → min 1 available
    │
    └─[4] module.monitoring
            ├── kubernetes_namespace      → monitoring
            ├── helm_release.prometheus   → kube-prometheus-stack
            └── kubernetes_ingress_v1     → grafana.local
```

## Key Design Decisions

| Decision | Rationale |
|---|---|
| Shell executor | Runner on Mac needs local cluster access |
| base64 -D | macOS decode flag (not -d like Linux) |
| envsubst for manifests | Clean substitution without templating engine |
| kubectl apply (not set image) | Handles first-run AND updates |
| Deployment owned by CI | Avoids chicken-and-egg with image |
| Traefik v3 | ingress-nginx EOL March 2026 |
| nginx port 8080 | Non-root container execution |
| containerd hosts.toml | HTTP registry in K8s 1.32+ |
| ngrok launchd service | Permanent URL, no terminal needed |
| Stage 1 / Stage 2 apply | kubeconfig must exist before providers |
