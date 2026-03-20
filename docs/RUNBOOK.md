# RUNBOOK.md — Day-2 Operations & Troubleshooting

---

## Daily Operations

### Check cluster health

```bash
export KUBECONFIG=./kubeconfig

# Node status
kubectl get nodes -o wide

# All pods across all namespaces
kubectl get pods -A

# Check for any pending or failed pods
kubectl get pods -A | grep -v Running | grep -v Completed
```

### Check application status

```bash
# App pods
kubectl get pods -n webapp -l app.kubernetes.io/name=react-app

# Deployment rollout status
kubectl rollout status deployment/react-app -n webapp

# Recent events
kubectl describe deployment react-app -n webapp | tail -20

# Pod logs
kubectl logs -n webapp -l app.kubernetes.io/name=react-app --tail=50

# Ingress
kubectl get ingress -n webapp
```

### View deployment history

```bash
# See all revisions
kubectl rollout history deployment/react-app -n webapp

# See what changed in a specific revision
kubectl rollout history deployment/react-app -n webapp --revision=3
```

---

## Deployment Operations

### Trigger a new deployment

Any push to the `main` branch triggers the full pipeline automatically:
```bash
git push origin main
```

### Manual rollback (via GitLab UI)

1. Go to **CI/CD → Pipelines** → find the last successful pipeline
2. Click the **rollback:kubernetes** job (right side)
3. Click **Run** — the manual trigger button
4. Monitor the job logs

### Manual rollback (via CLI)

```bash
# Rollback to previous revision
kubectl rollout undo deployment/react-app -n webapp

# Rollback to a specific revision
kubectl rollout undo deployment/react-app -n webapp --to-revision=2

# Wait for rollback to complete
kubectl rollout status deployment/react-app -n webapp
```

### Scale up/down (emergency)

```bash
# Scale up to 4 replicas
kubectl scale deployment/react-app -n webapp --replicas=4

# Scale back to normal (Terraform manages this, re-apply to restore)
kubectl scale deployment/react-app -n webapp --replicas=2
```

---

## Monitoring Operations

### Access Grafana

```bash
# Via Ingress (if /etc/hosts is configured)
open http://grafana.local

# Via port-forward (if Ingress is unavailable)
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring
open http://localhost:3000
# Login: admin / (TF_VAR_grafana_admin_password you set)
```

### Access Prometheus

```bash
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring
open http://localhost:9090
```

### Useful Prometheus queries

```promql
# HTTP request rate (RPS)
rate(nginx_ingress_controller_requests[5m])

# Error rate (%)
rate(nginx_ingress_controller_requests{status=~"5.."}[5m]) /
rate(nginx_ingress_controller_requests[5m]) * 100

# Pod memory usage
container_memory_usage_bytes{namespace="webapp"}

# Pod CPU usage
rate(container_cpu_usage_seconds_total{namespace="webapp"}[5m])

# Pod restarts
increase(kube_pod_container_status_restarts_total{namespace="webapp"}[1h])
```

---

## Troubleshooting Guide

### Problem: App not accessible at http://webapp.local

**Diagnosis:**
```bash
# 1. Check /etc/hosts
cat /etc/hosts | grep webapp.local

# 2. Check ingress exists
kubectl get ingress -n webapp

# 3. Check ingress controller pods
kubectl get pods -n ingress-nginx

# 4. Check ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=30

# 5. Test service directly
kubectl port-forward svc/react-app 8080:80 -n webapp
curl http://localhost:8080
```

**Fix:**
```bash
# Missing /etc/hosts entry
echo "127.0.0.1 webapp.local" | sudo tee -a /etc/hosts

# Ingress controller not ready — wait and retry
kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx
```

---

### Problem: Pipeline fails at docker:build-push

**Diagnosis:** Check CI job logs for the error message.

**Common causes:**
```
Error: unauthorized: authentication required
→ CI_REGISTRY_USER / CI_REGISTRY_PASSWORD not available
→ Solution: This is auto-set by GitLab. Check runner has access to registry.

Error: no space left on device
→ Docker layer cache full on runner
→ Solution: This resolves itself on next runner rotation.

Error: COPY failed: file not found in build context
→ app/dist/ artifact not passed from build:react stage
→ Solution: Check build:react stage completed successfully first.
```

---

### Problem: deploy:kubernetes fails — ImagePullBackOff

**Diagnosis:**
```bash
kubectl describe pod -n webapp -l app.kubernetes.io/name=react-app | grep -A 5 Events
# Look for: Failed to pull image "registry.gitlab.com/..."
```

**Fix:**
```bash
# Verify the registry pull secret exists
kubectl get secret -n webapp | grep registry-auth

# Check deploy token is still valid
# GitLab → Settings → Repository → Deploy tokens

# Recreate the secret via Terraform
export TF_VAR_registry_username="..."
export TF_VAR_registry_password="..."
terraform apply -target=module.k8s_app.kubernetes_secret.registry_auth
```

---

### Problem: Pod stuck in CrashLoopBackOff

**Diagnosis:**
```bash
# Check pod logs
kubectl logs -n webapp -l app.kubernetes.io/name=react-app --previous

# Check events
kubectl describe pod -n webapp -l app.kubernetes.io/name=react-app
```

**Common causes and fixes:**
```
nginx: [emerg] bind() to 0.0.0.0:80 failed
→ Port conflict — another process on port 80
→ Check: kubectl get pods -A | grep 80

OOMKilled
→ Memory limit exceeded (128Mi)
→ Increase limit in terraform/modules/k8s-app/main.tf
→ terraform apply

Liveness probe failed
→ App taking too long to start
→ Increase initialDelaySeconds in the deployment
```

---

### Problem: Terraform apply fails — cluster already exists

```bash
# Delete the existing cluster
kind delete cluster --name react-k8s-cluster

# Re-run Terraform
terraform apply
```

---

### Problem: kubeconfig not working after cluster restart

Kind clusters do not persist across Docker restarts (OrbStack restart = cluster gone).

```bash
# Check if cluster is running
kind get clusters

# If missing, recreate with Terraform
terraform apply

# Re-encode kubeconfig for GitLab CI
cat kubeconfig | base64 | tr -d '\n' | pbcopy
# Update the KUBE_CONFIG variable in GitLab CI/CD settings
```

---

## Cluster Maintenance

### Upgrade Kubernetes version

1. Update `kubernetes_version` in `terraform.tfvars`
2. Run `terraform plan` to preview
3. Kind clusters cannot be upgraded in-place — this recreates the cluster:
   ```bash
   terraform destroy
   terraform apply
   ```
4. Re-run the CI/CD pipeline to redeploy the application

### Clean up old Docker images (registry)

GitLab Container Registry → project → Packages & Registries → Container Registry  
→ react-app → select old tags → Delete

### Rotate deploy token

1. GitLab → Settings → Repository → Deploy tokens
2. Revoke the old token
3. Create a new one with same scopes
4. Update `TF_VAR_registry_password`
5. Run `terraform apply -target=module.k8s_app.kubernetes_secret.registry_auth`
6. Update CI/CD variable if used there

---

## Emergency Contacts / Escalation

*(Fill in your team details here)*

| Role | Contact | When to escalate |
|------|---------|-----------------|
| On-call engineer | — | App down > 5 minutes |
| Platform team | — | Cluster infrastructure issues |
| Security | — | Any suspected credential compromise |

---

*For architecture context, see [ARCHITECTURE.md](ARCHITECTURE.md)*  
*For security procedures, see [SECURITY.md](SECURITY.md)*
