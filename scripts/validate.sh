#!/usr/bin/env bash
# validate.sh - Pre-flight and post-deploy validation
GREEN='\033[32m'; CYAN='\033[36m'; AMBER='\033[33m'; RED='\033[31m'; RESET='\033[0m'
pass()    { echo -e "  ${GREEN}OK${RESET}  $1"; }
fail()    { echo -e "  ${RED}FAIL${RESET}  $1"; FAILED=$((FAILED+1)); }
warn()    { echo -e "  ${AMBER}WARN${RESET}  $1"; }
section() { echo -e "\n${CYAN}--- $1 ---${RESET}"; }
FAILED=0
KUBECONFIG_PATH="${KUBECONFIG:-./kubeconfig}"
NAMESPACE="webapp"
APP_NAME="react-app"
QUICK="${1:-}"

section "Required Tools"
for tool in git docker terraform kubectl helm ngrok; do
  command -v "$tool" &>/dev/null && pass "$tool installed" || fail "$tool not found"
done

section "Docker"
docker info &>/dev/null && pass "Docker running" || fail "Docker not running"

section "Environment Variables"
for var in TF_VAR_grafana_admin_password TF_VAR_registry_username TF_VAR_registry_password; do
  [ -n "${!var:-}" ] && pass "$var set" || fail "$var not set"
done

section "Project Files"
for f in ".gitlab-ci.yml" "Makefile" "app/Dockerfile" "app/package.json" \
  "terraform/main.tf" "terraform/versions.tf" \
  "terraform/modules/kind-cluster/main.tf" \
  "terraform/modules/k8s-app/main.tf" \
  "terraform/modules/monitoring/main.tf" \
  "kubernetes/deployment.yaml" "docs/SETUP.md" "docs/SECURITY.md"; do
  [ -f "$f" ] && pass "$f" || fail "$f MISSING"
done
[ -f "terraform/terraform.tfvars" ] && pass "terraform.tfvars" || fail "terraform.tfvars missing"
[ -f "terraform/.terraform.lock.hcl" ] && pass "terraform init done" || warn "terraform init not run"

section "kubeconfig"
if [ -f "$KUBECONFIG_PATH" ]; then
  pass "kubeconfig exists"
  perms=$(stat -f "%OLp" "$KUBECONFIG_PATH" 2>/dev/null || echo "unknown")
  [ "$perms" = "600" ] && pass "permissions 600" || fail "permissions $perms (need 600)"
else
  warn "kubeconfig not found"
fi

section "Kind Cluster (via Docker)"
docker ps 2>/dev/null | grep -q "react-k8s-cluster-control-plane" && \
  pass "Kind cluster running" || warn "Kind cluster not found"

section "Kubernetes"
if [ -f "$KUBECONFIG_PATH" ]; then
  export KUBECONFIG="$KUBECONFIG_PATH"
  kubectl cluster-info --request-timeout=5s &>/dev/null && pass "API server reachable" || fail "API unreachable"
  node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
  [ "${node_count:-0}" -ge 2 ] && pass "$node_count nodes" || warn "$node_count nodes"
  ready_count=$(kubectl get nodes --no-headers 2>/dev/null | grep " Ready" | wc -l | tr -d ' ')
  [ "${ready_count:-0}" -ge 2 ] && pass "all nodes Ready" || fail "$ready_count nodes Ready"
  kubectl get pods -n traefik --no-headers 2>/dev/null | grep -q "Running" && \
    pass "Traefik Running" || fail "Traefik not Running"
fi

section "Application"
if [ -f "$KUBECONFIG_PATH" ]; then
  export KUBECONFIG="$KUBECONFIG_PATH"
  kubectl get namespace "$NAMESPACE" &>/dev/null && pass "namespace $NAMESPACE" || warn "namespace missing"
  kubectl get service "$APP_NAME" -n "$NAMESPACE" &>/dev/null && pass "service exists" || warn "service missing"
  kubectl get ingress "$APP_NAME" -n "$NAMESPACE" &>/dev/null && pass "ingress exists" || warn "ingress missing"
  kubectl get hpa "$APP_NAME" -n "$NAMESPACE" &>/dev/null && pass "HPA exists" || warn "HPA missing"
  kubectl get pdb "$APP_NAME" -n "$NAMESPACE" &>/dev/null && pass "PDB exists" || warn "PDB missing"
  if kubectl get deployment "$APP_NAME" -n "$NAMESPACE" &>/dev/null; then
    desired=$(kubectl get deployment "$APP_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 0)
    ready=$(kubectl get deployment "$APP_NAME" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
    [ "${ready:-0}" -eq "$desired" ] && pass "$ready/$desired replicas ready" || fail "$ready/$desired replicas"
  else
    warn "deployment not found - run pipeline first"
  fi
  kubectl get secret "${APP_NAME}-registry-auth" -n "$NAMESPACE" &>/dev/null && \
    pass "pull secret exists" || warn "pull secret missing"
fi

section "Monitoring"
if [ -f "$KUBECONFIG_PATH" ]; then
  export KUBECONFIG="$KUBECONFIG_PATH"
  kubectl get namespace monitoring &>/dev/null && pass "namespace monitoring" || warn "monitoring namespace missing"
  kubectl get pods -n monitoring --no-headers 2>/dev/null | grep -q "prometheus.*Running" && \
    pass "Prometheus Running" || warn "Prometheus not Running"
  kubectl get pods -n monitoring --no-headers 2>/dev/null | grep -q "grafana.*Running" && \
    pass "Grafana Running" || warn "Grafana not Running"
fi

section "DNS"
grep -q "webapp.local" /etc/hosts && pass "webapp.local" || fail "webapp.local missing"
grep -q "grafana.local" /etc/hosts && pass "grafana.local" || fail "grafana.local missing"

if [ "$QUICK" != "--quick" ]; then
  section "HTTP"
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 http://webapp.local 2>/dev/null || echo "000")
  [ "$code" = "200" ] && pass "webapp.local HTTP $code" || fail "webapp.local HTTP $code"
fi

section "Security"
grep -q "terraform.tfvars" .gitignore && pass "tfvars gitignored" || fail "tfvars NOT gitignored"
grep -q "kubeconfig" .gitignore && pass "kubeconfig gitignored" || fail "kubeconfig NOT gitignored"
grep -q "\.envrc" .gitignore && pass ".envrc gitignored" || fail ".envrc NOT gitignored"

echo ""
if [ "$FAILED" -eq 0 ]; then
  echo -e "${GREEN}ALL CHECKS PASSED${RESET}"
else
  echo -e "${RED}$FAILED FAILED${RESET}"
  exit 1
fi
