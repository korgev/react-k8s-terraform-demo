# SECURITY.md — Security Posture & Reviewer Access Guide

## Reviewer Access

| Resource | URL | Notes |
|---|---|---|
| Source code | https://github.com/korgev/react-k8s-terraform-demo | Public, no account needed |
| On-prem app | https://mervin-tetrahydric-dwayne.ngrok-free.dev | Always-on, HTTPS |
| GKE app | https://acba.harmar.site | Real GCP LoadBalancer |
| Grafana (GKE) | https://grafana.harmar.site | admin / see SETUP.md |
| Grafana (on-prem) | http://grafana.local | Requires /etc/hosts entry |

Reviewer CANNOT: push code, modify CI variables, access clusters, push/delete images.

### Revoke after review
```bash
# GitLab CE → Settings → Repository → Deploy tokens → Revoke
# GCP → IAM → Service Accounts → disable gke-ci-runner if needed
```

---

## Secrets Inventory

| Secret | Storage | In Git? | Masked? |
|---|---|---|---|
| Grafana password | .envrc (gitignored) | ❌ Never | sensitive=true in TF |
| Registry deploy token | .envrc (gitignored) | ❌ Never | K8s secret sensitive=true |
| GitLab PAT (TF state) | .envrc (gitignored) | ❌ Never | TF_HTTP_PASSWORD env only |
| KUBE_CONFIG | GitLab CI var | ❌ Never | ✅ Masked + Protected |
| GCP_SA_KEY | GitLab CI var | ❌ Never | ✅ Masked |
| GKE_KUBE_CONFIG | GitLab CI var (deprecated) | ❌ Never | ✅ Masked |
| K8s pull secret | Terraform from env vars | ❌ Never | sensitive=true |
| GCP SA key JSON | Local only (gitignored) | ❌ Never | Not in CI logs |

**Rule: No secret appears in any committed file.**

---

## Container Security

### Multi-stage Dockerfile
- Stage 1 (builder): `node:20.11-alpine3.19` — compiles React app
- Stage 2 (server): `nginx:1.25-alpine3.18` — serves static files only
- Final image: ~44MB, zero build tools, zero npm packages
- On-prem: `linux/arm64` (Mac native)
- GKE: `linux/amd64` (built with `docker buildx --platform linux/amd64`)

### nginx non-root
Port 8080 enables full security context:
```yaml
runAsNonRoot: true
runAsUser: 101        # nginx uid
seccompProfile:
  type: RuntimeDefault
capabilities:
  drop: ["ALL"]
allowPrivilegeEscalation: false
```

### Image tags — immutable
- Format: `:$CI_COMMIT_SHORT_SHA` + `:v1.0.$CI_PIPELINE_IID`
- `:latest` never used — prevents silent image replacement
- OCI labels: source, revision, version on every image

---

## Kubernetes Security

### Pod Security Admission
- `webapp` namespace: `enforce=baseline`, `warn=restricted`
- `monitoring` namespace: `enforce=privileged` (node-exporter requires host PID)

### ServiceAccount
- Dedicated SA per app (`react-app`) — not `default`
- `automountServiceAccountToken: false` — app has no K8s API access

### Network
- Service type `ClusterIP` (on-prem) — all external traffic via Ingress
- Service type `LoadBalancer` (GKE) — GCP-managed, no node exposure

---

## CI/CD Security

| Practice | Implementation |
|---|---|
| Immutable image tags | git SHA + semver, never `:latest` |
| Secrets masked | Never appear in CI logs |
| Auto-rollback | Failed deployments revert automatically |
| Branch isolation | `main` → on-prem, `feature/gke` → GCP |
| Least-privilege SA | `gke-ci-runner` has only `container.developer` + `artifactregistry.writer` |
| Separate registries | On-prem uses GitLab CE, GKE uses Artifact Registry |

---

## GCP IAM

| Service Account | Roles | Purpose |
|---|---|---|
| `terraform-gcp` | container.admin, compute.networkAdmin, artifactregistry.admin | Terraform provisioning only |
| `gke-ci-runner` | container.developer, artifactregistry.writer | CI/CD pipeline only |
| `react-k8s-gke-node-sa` | artifactregistry.reader, logging.logWriter, monitoring.metricWriter | GKE node pool (least privilege) |

---

## Known Trade-offs vs Production

### GKE HTTP only (no HTTPS)
Risk: Traffic between user and GKE app is unencrypted.
Mitigation: Demo only — no sensitive data transmitted.
Production fix: GCP Certificate Manager + managed SSL cert + real domain.

### Catch-all Ingress (on-prem)
Risk: Accepts requests regardless of Host header.
Mitigation: Cluster behind ngrok, not directly internet-exposed.
Production fix: Real domain + cert-manager + `enable_catch_all_ingress=false`.

### GitLab CE HTTP Registry
Risk: Images transmitted over HTTP on local network.
Mitigation: `192.168.2.2` is local VM only, not internet-accessible.
Production fix: TLS cert on GitLab CE registry.

### Shell Executor GitLab Runner
Risk: CI jobs run directly on developer Mac.
Mitigation: Local demo only — no shared infrastructure at risk.
Production fix: Kubernetes executor with job-scoped service accounts.

### .envrc Unencrypted
Risk: Secrets stored in plaintext on disk.
Mitigation: Local developer machine only, gitignored, never committed.
Production fix: HashiCorp Vault or GCP Secret Manager.

### GCP SA Key in GitLab CI variable
Risk: Long-lived credentials if compromised.
Mitigation: Least-privilege roles, can be revoked instantly in GCP IAM.
Production fix: Workload Identity Federation (no key files at all).
