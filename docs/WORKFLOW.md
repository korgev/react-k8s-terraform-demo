# WORKFLOW.md — How the Solution Works

## Two Pipelines, One CI File

The single `.gitlab-ci.yml` runs different jobs based on branch:

| Branch | Pipeline | Registry | Cluster |
|---|---|---|---|
| `main` | On-prem | GitLab CE `:5050` | Kind (local) |
| `feature/gke` | GCP | Artifact Registry | GKE Autopilot |

---

## On-prem Pipeline Flow (main branch)
```
git push origin main
        │
        ▼
GitLab CE (192.168.2.2)
        │
┌───────────────────────────────────────┐
│ 1. test:build                         │
│    npm ci + eslint                    │
│         ↓                             │
│ 2. docker:build-push                  │
│    docker build (arm64)               │
│    push :SHA + :v1.0.N                │
│    → 192.168.2.2:5050                 │
│         ↓                             │
│ 3. deploy:kubernetes                  │
│    KUBE_CONFIG → ~/.kube/config       │
│    envsubst + kubectl apply           │
│    rollout status --timeout=180s      │
│    auto-rollback on failure           │
│         ↓                             │
│ 4. rollback (manual)                  │
│    kubectl rollout undo               │
└───────────────────────────────────────┘
        │
        ▼
Kind Cluster (OrbStack, K8s 1.32)
├── traefik ns    → Traefik v3 (80/443)
├── webapp ns     → react-app (nginx:8080)
│                   Service, Ingress, HPA, PDB
└── monitoring    → Prometheus + Grafana
        │
        ▼
ngrok launchd (background, permanent)
        │
        ▼
https://mervin-tetrahydric-dwayne.ngrok-free.dev
```

---

## GKE Pipeline Flow (feature/gke branch)
```
git push origin feature/gke
        │
        ▼
GitLab CE (192.168.2.2)
        │
┌───────────────────────────────────────┐
│ 1. test:build                         │
│    npm ci + eslint (shared)           │
│         ↓                             │
│ 2. docker:build-push-gcp             │
│    gcloud auth (SA key)               │
│    docker buildx --platform amd64    │
│    push :SHA + :v1.0.N               │
│    → us-central1-docker.pkg.dev      │
│         ↓                             │
│ 3. deploy:kubernetes-gcp             │
│    gcloud auth activate-sa           │
│    gcloud get-credentials            │
│    envsubst + kubectl apply           │
│    rollout status --timeout=300s      │
│    auto-rollback on failure           │
│         ↓                             │
│ 4. rollback:kubernetes-gcp (manual)  │
│    kubectl rollout undo               │
└───────────────────────────────────────┘
        │
        ▼
GKE Autopilot (us-central1, K8s 1.34)
├── webapp ns     → react-app (nginx:8080)
│                   LoadBalancer Service
└── monitoring    → Grafana
        │
        ▼
https://acba.harmar.site (GCP Cloud LoadBalancer)
```

---

## Terraform Infrastructure Flow

### On-prem
```
terraform apply (terraform/)
    │
    ├─[1] module.kind_cluster
    │       ├── kind_cluster.this       → 2-node K8s cluster
    │       ├── local_file.kubeconfig   → ./kubeconfig (0600)
    │       └── null_resource.registry → containerd hosts.toml
    │
    ├─[2] helm_release.traefik         → Traefik v3 ingress
    │
    ├─[3] module.k8s_app
    │       ├── kubernetes_namespace    → webapp + PSA labels
    │       ├── kubernetes_service_account
    │       ├── kubernetes_secret       → registry pull secret
    │       ├── kubernetes_service      → ClusterIP 80→8080
    │       ├── kubernetes_ingress_v1   → catch-all rule
    │       ├── kubernetes_hpa          → CPU 70%, 2-6 replicas
    │       └── kubernetes_pdb          → minAvailable=1
    │
    └─[4] module.monitoring
            ├── kubernetes_namespace    → monitoring
            ├── helm_release.prometheus → kube-prometheus-stack
            └── kubernetes_ingress_v1  → grafana.local
```

### GCP (phased — kubeconfig must exist before K8s providers init)
```
make gcp-apply
    │
    ├─ Phase 1: terraform apply -target=module.gke_cluster
    │       ├── google_compute_network         → custom VPC
    │       ├── google_compute_subnetwork      → with pod/svc ranges
    │       ├── google_compute_firewall        → internal allow
    │       ├── google_service_account         → node SA
    │       ├── google_project_iam_member (x3) → least-privilege roles
    │       ├── google_container_cluster       → GKE Autopilot
    │       └── local_file.kubeconfig          → ./kubeconfig-gke
    │
    └─ Phase 2: terraform apply
            ├── module.k8s_app
            │       ├── kubernetes_namespace   → webapp
            │       ├── kubernetes_service     → LoadBalancer (GKE)
            │       ├── kubernetes_ingress_v1
            │       ├── kubernetes_hpa
            │       └── kubernetes_pdb
            └── monitoring-gcp.tf
                    ├── kubernetes_namespace   → monitoring
                    └── helm_release.grafana   → Grafana (lightweight)
```

---

## Key Design Decisions

| Decision | Rationale |
|---|---|
| Shell executor | Runner on Mac needs local cluster + gcloud access |
| `base64 -D` | macOS decode flag (Linux uses `-d`) |
| `envsubst` for manifests | Clean substitution without Helm templating |
| `kubectl apply` (not `set image`) | Handles first-run AND updates idempotently |
| Deployment owned by CI | Avoids chicken-and-egg — image must exist first |
| Traefik v3 (on-prem) | ingress-nginx EOL March 2026 |
| GCP LoadBalancer (GKE) | Native GKE service, no ingress controller needed |
| nginx port 8080 | Non-root container — can't bind port 80 |
| containerd hosts.toml | Required for HTTP registry in K8s 1.32+ |
| ngrok launchd service | Permanent URL, survives reboots, no terminal |
| GCS state (GKE) | Native GCP, built-in locking, versioned |
| SA key for CI (GKE) | Access tokens expire in 1h — SA key is permanent |
| linux/amd64 buildx | Mac builds arm64 by default — GKE needs amd64 |
| Phased terraform apply | Providers need kubeconfig before K8s resources |
