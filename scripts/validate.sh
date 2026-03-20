#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# validate.sh — Pre-flight and post-deploy validation
# Usage:
#   bash scripts/validate.sh           # all checks
#   bash scripts/validate.sh --quick   # skip HTTP check
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

GREEN='\033[32m'; CYAN='\033[36m'; AMBER='\033[33m'; RED='\033[31m'; RESET='\033[0m'
pass()    { echo -e "  ${GREEN}✅ PASS${RESET}  $1"; }
fail()    { echo -e "  ${RED}❌ FAIL${RESET}  $1"; FAILED=$((FAILED+1)); }
warn()    { echo -e "  ${AMBER}⚠️  WARN${RESET}  $1"; }
section() { echo -e "\n${CYAN}─── $1 ────────────────────────────────────────${RESET}"; }

FAILED=0
KUBECONFIG_PATH="${KUBECONFIG:-./kubeconfig}"
NAMESPACE="webapp"
APP_NAME="react-app"
QUICK="${1:-}"

# ─── Tools ────────────────────────────────────────────────────────────────────
section "Required Tools"
for tool in git docker terraform kind kubectl helm; do
  command -v "$tool" &>/dev/null && pass "$tool installed" || fail "$tool not found — see docs/SETUP.md"
done
command -v ngrok &>/dev/null && pass "ngrok installed" || warn "ngrok not found — needed for public reviewer URL"

# ─── Docker ───────────────────────────────────────────────────────────────────
section "Docker / OrbStack"
docker info &>/dev/null && pass "Docker daemon is running" || \
  fail "Docker not running — open OrbStack"

# ─── Environment Variables ────────────────────────────────────────────────────
section "Environment Variables (TF_VAR_*)"
for var in TF_VAR_grafana_admin_password TF_VAR_registry_username TF_VAR_registry_password; do
  [ -n "${!var:-}" ] && pass "$var set" || fail "$var not set — run: source .envrc"
done

# ─── Project Files ────────────────────────────────────────────────────────────
section "Project Files"
for f in \
  ".gitlab-ci.yml" \
  "Makefile" \
  "app/Dockerfile" \
  "app/package.json" \
  "terraform/main.tf" \
  "terraform/versions.tf" \
  "terraform/modules/kind-cluster/main.tf" \
  "terraform/modules/k8s-app/main.tf" \
  "terraform/modules/monitoring/main.tf" \
  "kubernetes/deployment.yaml" \
  "docs/SETUP.md" \
  "docs/SECURITY.md"; do
  [ -f "$f" ] && pass "$f exists" || fail "$f MISSING"
done

[ -f "terraform/terraform.tfvars" ] && pass "terraform.tfvars exists" || \
  fail "terraform.tfvars missing — copy from terraform.tfvars.example and edit"

[ -f "terraform/.terraform.lock.hcl" ] && pass "terraform init has been run" || \
  warn "terraform init not run — run: cd terraform && terraform init"

# ─── kubeconfig ───────────────────────────────────────────────────────────────
section "kubeconfig"
if [ -f "$KUBECONFIG_PATH" ]; then
  pass "kubeconfig exists at $KUBECONFIG_PATH"
  perms=$(stat -f "%OLp" "$KUBECONFIG_PATH" 2>/dev/null || stat -c "%a" "$KUBECONFIG_PATH" 2>/dev/null || echo "unknown")
  [ "$perms" = "600" ] && pass "kubeconfig permissions: 600 (owner-only)" || \
    fail "kubeconfig permissions: $perms — fix with: chmod 600 $KUBECONFIG_PATH"
else
  warn "kubeconfig not found — run: make tf-apply"
fi

# ─── Kind Cluster ─────────────────────────────────────────────────────────────
section "Kind Cluster"
if kind get clusters 2>/dev/null | grep -q "react-k8s-cluster"; then
  pass "Kind cluster 'react-k8s-cluster' exists"
else
  warn "Kind cluster not found — run: make tf-apply"
fi

# ─── Kubernetes ───────────────────────────────────────────────────────────────
section "Kubernetes Cluster"
if [ -f "$KUBECONFIG_PATH" ]; then
  export KUBECONFIG="$KUBECONFIG_PATH"

  kubectl cluster-info --request-timeout=5s &>/dev/null && \
    pass "API server reachable" || fail "Cannot reach K8s API server"

  node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
  [ "$node_count" -ge 2 ] && pass "$node_count nodes in cluster" || \
    warn "Only $node_count node(s) — expected 2 (control-plane + worker)"

  not_ready=$(kubectl get nodes --no-headers 2>/dev/null | grep -v " Ready" | wc -l | tr -d ' ')
  [ "$not_ready" -eq 0 ] && pass "All nodes Ready" || fail "$not_ready node(s) not Ready"

  # Ingress controller
  ingress_running=$(kubectl get pods -n ingress-nginx --no-headers 2>/dev/null | grep "Running" | wc -l | tr -d ' ')
  [ "${ingress_running:-0}" -ge 1 ] && pass "nginx-ingress controller Running" || \
    warn "nginx-ingress not Running — may still be starting"
fi

# ─── Application ──────────────────────────────────────────────────────────────
section "Application (Kubernetes)"
if [ -f "$KUBECONFIG_PATH" ]; then
  export KUBECONFIG="$KUBECONFIG_PATH"

  kubectl get namespace "$NAMESPACE" &>/dev/null && \
    pass "namespace/$NAMESPACE exists" || warn "namespace/$NAMESPACE missing — run terraform apply"

  kubectl get service "$APP_NAME" -n "$NAMESPACE" &>/dev/null && \
    pass "service/$APP_NAME exists" || warn "service/$APP_NAME missing"

  kubectl get ingress "$APP_NAME" -n "$NAMESPACE" &>/dev/null && \
    pass "ingress/$APP_NAME exists" || warn "ingress/$APP_NAME missing"

  kubectl get hpa "$APP_NAME" -n "$NAMESPACE" &>/dev/null && \
    pass "hpa/$APP_NAME exists" || warn "hpa/$APP_NAME missing"

  kubectl get pdb "$APP_NAME" -n "$NAMESPACE" &>/dev/null && \
    pass "pdb/$APP_NAME exists" || warn "pdb/$APP_NAME missing"

  # Deployment (created by CI — may not exist before first pipeline run)
  if kubectl get deployment "$APP_NAME" -n "$NAMESPACE" &>/dev/null; then
    pass "deployment/$APP_NAME exists"
    desired=$(kubectl get deployment "$APP_NAME" -n "$NAMESPACE" \
      -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 0)
    ready=$(kubectl get deployment "$APP_NAME" -n "$NAMESPACE" \
      -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
    [ "${ready:-0}" -eq "$desired" ] && \
      pass "$ready/$desired replicas ready" || \
      fail "Only ${ready:-0}/$desired replicas ready"
  else
    warn "deployment/$APP_NAME not found — run the GitLab CI/CD pipeline first"
  fi

  # Pull secret
  kubectl get secret "${APP_NAME}-registry-auth" -n "$NAMESPACE" &>/dev/null && \
    pass "registry pull secret exists" || warn "registry pull secret missing"
fi

# ─── Monitoring ───────────────────────────────────────────────────────────────
section "Monitoring Stack"
if [ -f "$KUBECONFIG_PATH" ]; then
  export KUBECONFIG="$KUBECONFIG_PATH"

  kubectl get namespace monitoring &>/dev/null && pass "namespace/monitoring exists" || \
    warn "namespace/monitoring missing — monitoring not yet deployed"

  prom=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep "prometheus-kube" | grep "Running" | wc -l | tr -d ' ')
  [ "${prom:-0}" -ge 1 ] && pass "Prometheus Running" || warn "Prometheus not Running yet"

  grafana=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep "grafana" | grep "Running" | wc -l | tr -d ' ')
  [ "${grafana:-0}" -ge 1 ] && pass "Grafana Running" || warn "Grafana not Running yet"
fi

# ─── DNS ──────────────────────────────────────────────────────────────────────
section "/etc/hosts DNS"
grep -q "webapp.local"   /etc/hosts && pass "webapp.local in /etc/hosts"   || \
  fail "webapp.local missing — run: make add-hosts"
grep -q "grafana.local"  /etc/hosts && pass "grafana.local in /etc/hosts"  || \
  fail "grafana.local missing — run: make add-hosts"

# ─── HTTP ─────────────────────────────────────────────────────────────────────
if [ "$QUICK" != "--quick" ]; then
  section "HTTP Connectivity"
  if grep -q "webapp.local" /etc/hosts 2>/dev/null; then
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 http://webapp.local 2>/dev/null || echo "000")
    [ "$code" = "200" ] && pass "http://webapp.local → HTTP 200 OK" || \
      fail "http://webapp.local → HTTP $code (expected 200)"
  else
    warn "Skipping HTTP check — webapp.local not in /etc/hosts"
  fi
fi

# ─── Security sanity ──────────────────────────────────────────────────────────
section "Security Checks"
grep -q "terraform.tfvars"  .gitignore && pass "terraform.tfvars is gitignored" || \
  fail "terraform.tfvars not in .gitignore — secrets could be committed!"
grep -q "kubeconfig"        .gitignore && pass "kubeconfig is gitignored" || \
  fail "kubeconfig not in .gitignore!"
grep -q "\.envrc"           .gitignore && pass ".envrc is gitignored" || \
  fail ".envrc not in .gitignore!"
[ ! -f ".envrc" ] || ! git ls-files --error-unmatch .envrc &>/dev/null 2>&1 && \
  pass ".envrc not tracked by git" || fail ".envrc is tracked by git — remove it!"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
if [ "$FAILED" -eq 0 ]; then
  echo -e "${GREEN}══════════════════════════════════════════════════${RESET}"
  echo -e "${GREEN}  ✅  ALL CHECKS PASSED — ready to share!${RESET}"
  echo -e "${GREEN}══════════════════════════════════════════════════${RESET}"
  echo ""
  echo "  Next: make share  (starts ngrok tunnel for reviewer)"
else
  echo -e "${RED}══════════════════════════════════════════════════${RESET}"
  echo -e "${RED}  ❌  $FAILED CHECK(S) FAILED — fix above issues${RESET}"
  echo -e "${RED}══════════════════════════════════════════════════${RESET}"
  exit 1
fi
