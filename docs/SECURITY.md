# SECURITY.md — Security Posture & Reviewer Access Guide

## Reviewer Access Model

| Resource | Access | Permissions | Expiry |
|---|---|---|---|
| Source code | GitHub public mirror | Read only | Permanent |
| Running app | ngrok HTTPS static domain | View app | Permanent |
| Grafana | Ingress http://grafana.local | Read dashboards | Session |
| Container Registry | Deploy token read_registry | Pull images only | 90 days |

Reviewer CANNOT: push code, modify CI variables, access cluster, push/delete images.

### Reviewer access instructions

Source code — GitHub public mirror (no account needed):
https://github.com/YOUR_USERNAME/react-k8s-terraform-demo

Running app — always-on public URL:
https://mervin-tetrahydric-dwayne.ngrok-free.dev

Grafana — add to /etc/hosts first (127.0.0.1 grafana.local):
http://grafana.local  (admin / see SETUP.md)

### Revoke after review

GitLab CE — Settings → Repository → Deploy tokens → Revoke

## Secrets Inventory

| Secret | Storage | In Git? | In Logs? |
|---|---|---|---|
| Grafana password | .envrc (gitignored) | Never | sensitive=true |
| Registry deploy token | .envrc (gitignored) | Never | K8s secret sensitive |
| GitLab PAT (TF state) | .envrc (gitignored) | Never | Masked CI var |
| KUBE_CONFIG | GitLab CI var masked+protected | Never | Masked |
| K8s pull secret | Terraform from env vars | Never | (sensitive value) |

Rule: No secret appears in any committed file.

## Container Security

### Multi-stage Dockerfile
Stage 1 (builder): node:20-alpine — compiles code
Stage 2 (server): nginx:1.25-alpine — serves static files only
Final image: ~44MB, zero build tools, zero npm packages.

### nginx non-root
Port 8080 enables:
- runAsNonRoot: true + runAsUser: 101 (nginx uid)
- Drop ALL capabilities
- seccompProfile: RuntimeDefault
- allowPrivilegeEscalation: false

### Image labels (OCI standard)
Every image is traceable:
- org.opencontainers.image.source = GitLab project URL
- org.opencontainers.image.revision = git commit SHA
- org.opencontainers.image.created = build timestamp

## Kubernetes Security

### Pod SecurityContext
```yaml
runAsNonRoot: true
runAsUser: 101
seccompProfile:
  type: RuntimeDefault
capabilities:
  drop: ["ALL"]
allowPrivilegeEscalation: false
```

### ServiceAccount
- Dedicated SA per app (not default)
- automountServiceAccountToken: false

## CI/CD Security

| Practice | Implementation |
|---|---|
| Build once | Same SHA image deployed everywhere |
| Immutable tags | git SHA, never overwritten |
| Secrets masked | KUBE_CONFIG never appears in logs |
| Auto-rollback | Failed deployments revert automatically |
| Credential separation | CI uses CI_REGISTRY_*, K8s uses deploy token |

## Known Security Trade-offs

### Catch-all Ingress
Risk: Accepts requests regardless of Host header.
Mitigation: Cluster is local, behind ngrok, not directly internet-exposed.
Production fix: Stable domain + cert-manager + enable_catch_all_ingress=false.

### GitLab CE HTTP Registry
Risk: Images transmitted over HTTP on local network.
Mitigation: 192.168.2.2 is local VM only.
Production fix: TLS cert on registry.

### Shell Executor GitLab Runner
Risk: CI jobs run directly on developer Mac.
Mitigation: Local demo only — no shared infrastructure at risk.
Production fix: Kubernetes executor with job-scoped service accounts.

### .envrc Unencrypted
Risk: Secrets stored in plaintext on disk.
Mitigation: Local developer machine only, gitignored.
Production fix: HashiCorp Vault or cloud KMS.
