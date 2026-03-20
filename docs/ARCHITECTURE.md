# ARCHITECTURE.md — Design Decisions & Technical Deep Dive

---

## Why These Technology Choices

### Kind over Minikube or K3s

| Criterion | Kind | Minikube | K3s |
|-----------|------|----------|-----|
| macOS Apple Silicon support | ✅ native via Docker | ⚠️ Docker driver only | ❌ needs Lima VM |
| Terraform provider | ✅ `tehcyx/kind` | ⚠️ limited | ❌ none |
| Reviewer reproducibility | ✅ one tool (Docker) | ⚠️ driver-dependent | ❌ Linux-first |
| Multi-node | ✅ config YAML | ✅ | ✅ |

**Decision:** Kind runs entirely inside Docker. Anyone with Docker installed can spin up the identical cluster with one command. This maximises reviewer reproducibility without cloud costs.

### OrbStack over Docker Desktop

- 50-70% lower memory usage on Apple Silicon
- Faster VM startup
- Identical `docker` CLI interface — zero workflow change
- Free for personal/dev use
- Reviewer gets same environment by installing OrbStack

### GitLab.com over self-hosted GitLab CE

The task mentions "Setup GitLab CE". On a local macOS laptop, self-hosted GitLab CE requires ~8 GB RAM just for GitLab itself — which would compete with the Kind cluster.

**Architectural decision:** Use GitLab.com (the SaaS product), which provides the full GitLab CE feature set (CI/CD, Container Registry, Issue tracker, RBAC) without the resource overhead. The CI/CD pipelines, registry, and RBAC are functionally identical to self-hosted.

If a self-hosted GitLab is strictly required, it should be deployed to a cloud VM (e.g. GCP e2-standard-2) rather than locally.

### React + Vite over Angular or CRA

- Vite produces significantly smaller bundles than CRA
- Faster CI build times (important for the pipeline demo)
- Single-page app served by Nginx — zero server-side dependencies
- Build-time env vars (VITE_ prefix) allow injecting version metadata into the UI

---

## Kubernetes Architecture Decisions

### Two-node cluster (1 control-plane + 1 worker)

```
control-plane node:
  - labeled: ingress-ready=true
  - port mappings: 80/443 → host (required for Kind ingress)
  - runs: ingress controller, kube-system pods

worker node:
  - runs: react-app pods, monitoring stack
  - no ingress label (separation of concerns)
```

A single-node cluster would work but mixing control-plane and application workloads is not representative of production architecture. The two-node model demonstrates understanding of node roles.

### ClusterIP + Ingress over NodePort/LoadBalancer

In Kind, `LoadBalancer` services have no external IP without MetalLB.  
`NodePort` works but exposes arbitrary ports — not clean for production.

**Chosen pattern:**
```
External traffic
    → Nginx Ingress Controller (NodePort 80/443 on control-plane)
    → Routes to ClusterIP service by Host header
    → ClusterIP forwards to pod
```

This matches production Kubernetes patterns exactly (AWS ALB, GCP LB, etc. all terminate at an Ingress Controller).

### Deployment Strategy: RollingUpdate

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1        # spin up 1 new pod before removing old
    maxUnavailable: 0  # never have 0 pods serving traffic
```

With `replicas: 2`:
1. New pod (v2) starts — now 3 pods total
2. New pod passes readiness probe
3. Old pod (v1) terminated — back to 2 pods
4. Process repeats for second pod

Zero downtime guaranteed by `maxUnavailable: 0`.

### Pod Scheduling: TopologySpreadConstraint

```yaml
topologySpreadConstraint:
  maxSkew: 1
  topologyKey: kubernetes.io/hostname
  whenUnsatisfiable: DoNotSchedule
```

Ensures the 2 replicas land on different nodes. Without this, both pods could land on the same worker node — a single node failure would cause full downtime.

### Resource Requests and Limits

```yaml
resources:
  requests:
    cpu: 50m       # scheduler reserves this on a node
    memory: 64Mi
  limits:
    cpu: 200m      # hard cap — throttled but not killed
    memory: 128Mi  # hard cap — OOMKilled if exceeded
```

Setting requests without limits is dangerous (noisy neighbour problem).  
Setting limits without requests causes scheduling chaos.  
Both must be set for production workloads.

---

## CI/CD Pipeline Architecture

### Artifact passing between stages

```
build:react
  └── produces: app/dist/ (artifact, 1hr expiry)
         │
docker:build-push
  └── receives: app/dist/ (via needs + artifacts)
  └── produces: build.env (IMAGE_FULL=registry.../react-app:abc1234)
         │
deploy:kubernetes
  └── receives: build.env (knows exact image to deploy)
  └── produces: rollback.env (PREVIOUS_IMAGE=...previous tag)
         │
rollback:kubernetes
  └── receives: rollback.env (knows what to roll back to)
```

This "artifact pipeline" pattern ensures:
- Each stage knows exactly what the previous stage built
- Rollback knows exactly which image to restore
- No environment variable guessing

### Immutable image tagging

```bash
IMAGE_TAG = $CI_COMMIT_SHORT_SHA  # e.g. "a3f9b12"
```

- Every push creates a new tag = the git commit SHA
- Tags are **never overwritten** — full audit trail
- `latest` is also pushed for convenience (humans) but pipelines always use SHA tags
- Rolling back = deploying a previous SHA tag — fully reversible

### Auto-rollback vs Manual rollback

Two rollback mechanisms exist:

**Automatic** (in deploy stage):
```bash
if ! kubectl rollout status --timeout=180s; then
  kubectl rollout undo ...
  exit 1
fi
```
Triggered when new pods fail health checks within 3 minutes.

**Manual** (rollback stage):
```yaml
when: manual  # button in GitLab UI
```
Triggered by human decision — for cases where deployment succeeded but app is broken (business logic errors, not container errors).

---

## Terraform Module Architecture

### Module boundaries

```
terraform/
├── modules/kind-cluster/    # Infrastructure layer
│   Concern: "Does a cluster exist?"
│   Inputs:  cluster_name, k8s_version
│   Outputs: kubeconfig_path, cluster_name, endpoint
│
├── modules/k8s-app/         # Application layer
│   Concern: "Is the app running in K8s?"
│   Inputs:  image, replicas, namespace, credentials
│   Outputs: deployment_name, service_name, ingress_host
│
└── modules/monitoring/      # Observability layer
    Concern: "Can we see what's happening?"
    Inputs:  grafana_password
    Outputs: (grafana endpoint)
```

Each module has a single responsibility and can be versioned, reused, or replaced independently. This mirrors how production teams structure Terraform — platform team owns `kind-cluster`, app team owns `k8s-app`.

### Dependency graph

```
kind_cluster
    │
    ├──▶ nginx_ingress (helm_release, root level)
    │
    ├──▶ k8s_app (depends_on kind_cluster)
    │
    └──▶ monitoring (depends_on kind_cluster + nginx_ingress)
```

Explicit `depends_on` prevents Terraform from trying to deploy pods before the cluster exists.

---

## Monitoring Architecture

### kube-prometheus-stack components

```
kube-prometheus-stack Helm chart
├── Prometheus Operator        — manages Prometheus as K8s custom resource
├── Prometheus                 — metrics collection + storage (7-day retention)
├── Alertmanager               — alert routing (email/Slack hooks)
├── Grafana                    — dashboards + visualisation
├── node-exporter              — host-level metrics (CPU, RAM, disk, net)
├── kube-state-metrics         — K8s object metrics (pod counts, deployments)
└── Pre-built dashboards       — Kubernetes cluster, node, namespace views
```

### What gets monitored

**Infrastructure level (automatic):**
- Node CPU, memory, disk, network (node-exporter)
- Pod counts, restarts, resource usage (kube-state-metrics)
- Control plane components

**Application level (ingress metrics):**
- HTTP request count by status code
- Request rate (RPS)
- Error rate (5xx responses)
- Response latency (p50/p95/p99)

These come from the Nginx Ingress Controller which exports Prometheus metrics automatically.

### Golden Signals for this app

| Signal | Metric | Alert Threshold |
|--------|--------|-----------------|
| Latency | `nginx_ingress_controller_request_duration_seconds` | p99 > 1s |
| Traffic | `nginx_ingress_controller_requests` (rate) | informational |
| Errors | `nginx_ingress_controller_requests{status=~"5.."}` | error rate > 1% |
| Saturation | `container_memory_usage_bytes` | > 90% of limit |

---

## Production Readiness Assessment

| Category | This Solution | Production Gap |
|----------|---------------|----------------|
| High Availability | 2 replicas, PDB, rolling deploy | Multi-AZ nodes, external LB |
| Observability | Prometheus + Grafana + golden signals | Alertmanager → PagerDuty, tracing (Jaeger/Tempo) |
| Security | PSA, RBAC, no secrets in code | OPA/Kyverno policies, image signing (cosign) |
| Scalability | HPA on CPU | KEDA for event-driven scaling |
| GitOps | Push-based (kubectl in CI) | Pull-based (ArgoCD/FluxCD) |
| TLS | None (local only) | cert-manager + Let's Encrypt |
| State backend | Local `.tfstate` | GitLab HTTP backend or S3+DynamoDB |

This solution prioritises demonstrating all required capabilities within a local environment. Each production gap is a known trade-off, not an oversight.
