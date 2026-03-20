# SECURITY.md — Security Posture & Reviewer Access Guide

---

## Reviewer Access Model

This section defines exactly what access is granted to external reviewers,
what they can and cannot do, and how to revoke it.

### What the reviewer can access

| Resource | Access Type | Permissions | Expiry |
|----------|-------------|-------------|--------|
| GitLab Project | Guest role | Read code, view pipelines, read CI logs | Revoke after review |
| Container Registry | Deploy token | Pull images only (`read_registry`) | 90 days (set at creation) |
| App URL (ngrok) | Public HTTP | View running app only | Session-based |
| Grafana | Port-forward or Ingress | Read-only dashboards | Session-based |

### What the reviewer CANNOT do

- ❌ Push code or create branches
- ❌ Modify CI/CD variables or pipeline settings
- ❌ Access your GitLab personal account settings
- ❌ Access the Kubernetes cluster directly (no kubeconfig shared)
- ❌ Push or delete Docker images
- ❌ Access Terraform state

### Granting reviewer access — step by step

**1. Add reviewer as Guest on GitLab project:**
```
GitLab Project → Members → Invite member
Role: Guest (read-only — cannot push code or see CI variables)
Expiry: set 7 days from review date
```

**2. Share the ngrok public URL** (from SETUP.md Phase 10).

**3. Optionally share Grafana** read-only:
```bash
# Create read-only Grafana viewer account via API
# Or just share credentials for a dedicated viewer account
# Never share the admin password
```

### Revoking access after review

```
GitLab Project → Members → find reviewer → Remove member
GitLab Project → Settings → Repository → Deploy tokens → Revoke token
Stop ngrok session (Ctrl+C in terminal)
```

---

## Security Decisions & Rationale

### 1. Secrets Management

| Secret | Storage Method | Rationale |
|--------|----------------|-----------|
| kubeconfig | GitLab CI Variable (protected + masked) | Never in git; masked prevents log exposure |
| Registry deploy token | GitLab CI Variable (masked) | Scoped to `read_registry` only |
| Grafana password | Terraform env var (`TF_VAR_`) | Never in `.tfvars` or state output |
| Registry pull secret | Kubernetes Secret (created by Terraform) | Namespace-scoped; not accessible cross-namespace |

**Rule:** No secret appears in any file that is committed to git. All secrets are injected at runtime via environment variables or CI/CD variable store.

### 2. Container Image Security

**Multi-stage Dockerfile:**
```
Stage 1 (builder) — node:20-alpine   → compiles code, has npm, build tools
Stage 2 (server)  — nginx:1.25-alpine → serves files ONLY, no build tools
```
- Final image contains zero npm packages, no shell scripts, no build utilities
- Attack surface is limited to nginx + static HTML/JS/CSS
- Image pinned to exact versions (no `latest` tags in Dockerfile)

**Image labels (OCI standard):**
```
org.opencontainers.image.source   = GitLab project URL
org.opencontainers.image.revision = git commit SHA
org.opencontainers.image.created  = build timestamp
```
Every image is traceable back to the exact commit and pipeline that built it.

### 3. Kubernetes Security

**Namespace isolation:**
- `webapp` namespace — application workloads only
- `monitoring` namespace — observability tools only
- `ingress-nginx` namespace — ingress controller only
- No cross-namespace service access configured

**Pod Security Admission (PSA):**
```yaml
pod-security.kubernetes.io/enforce: baseline
pod-security.kubernetes.io/warn: restricted
```
Blocks privileged containers, host network access, and dangerous capabilities.

**SecurityContext per container:**
```yaml
allowPrivilegeEscalation: false
capabilities:
  drop: ["ALL"]
  add: ["NET_BIND_SERVICE"]  # only what nginx needs
```

**ServiceAccount:**
- Dedicated SA per application (no `default` SA used)
- `automountServiceAccountToken: false` — app has no K8s API access

**Pod Disruption Budget:**
- `minAvailable: 1` — ensures at least 1 pod survives node drain

### 4. Network Security

**Ingress:**
- All external traffic enters via Nginx Ingress Controller only
- Internal services use `ClusterIP` (not exposed externally)
- No `NodePort` or `LoadBalancer` services on application pods

**Nginx security headers (set in nginx.conf):**
```
X-Frame-Options: SAMEORIGIN          — prevents clickjacking
X-Content-Type-Options: nosniff      — prevents MIME sniffing
X-XSS-Protection: 1; mode=block     — XSS filter
Referrer-Policy: strict-origin-...  — limits referrer leakage
Permissions-Policy: camera=(), ...  — disables browser APIs
server_tokens: off                   — hides nginx version
```

### 5. CI/CD Security

**Build principles:**
- **Build once, deploy many** — same image SHA deployed everywhere
- **Immutable artifacts** — image tagged with git SHA, never overwritten
- **No secrets in pipeline logs** — all secret variables are masked

**Automatic rollback on failed deployment:**
```yaml
# In .gitlab-ci.yml deploy stage:
if ! kubectl rollout status ... --timeout=180s; then
  kubectl rollout undo deployment/react-app -n webapp
  exit 1
fi
```
If the new image fails to start within 3 minutes, the previous version is automatically restored.

**Deployment history:**
Every deployment annotated with:
```
kubernetes.io/change-cause: "GitLab pipeline <ID> — <SHA> — <message>"
```
Full audit trail of who deployed what and when.

### 6. Terraform Security

**No sensitive values in state output:**
```hcl
output "kubeconfig" {
  sensitive = true  # never printed to terminal or stored in CI logs
}
```

**Variable handling:**
```bash
# Sensitive vars always via environment, never in .tfvars
export TF_VAR_grafana_admin_password="..."
export TF_VAR_registry_password="..."
```

**`.gitignore` protections:**
```
terraform.tfvars     # blocked from git
*.tfstate            # blocked from git
kubeconfig           # blocked from git
```

### 7. Access Token Scoping

| Token | Scope | Rationale |
|-------|-------|-----------|
| GitLab Deploy Token | `read_registry` only | K8s only needs to pull images |
| GitLab CI Token | Auto-scoped to project | Built-in, rotates per pipeline |
| Terraform state token | Project-scoped | Only if using GitLab HTTP backend |

---

## Threat Model Summary

| Threat | Mitigation |
|--------|-----------|
| Secret leakage via git commit | .gitignore + pre-commit awareness |
| Malicious image in registry | Image tagged to git SHA; pull-only deploy token |
| Privilege escalation in container | SecurityContext + PSA baseline |
| Pipeline credential theft | Protected + masked CI variables |
| Reviewer over-permission | Guest role only; no CI variable visibility |
| Cluster credential leakage | kubeconfig never shared; base64+masked in CI only |
| Stale reviewer access | Expiry dates on all reviewer tokens |

---

*This document should be reviewed before sharing access with any external party.*
