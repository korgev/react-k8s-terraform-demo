#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# deploy-token-setup.sh
# Interactive helper for creating the GitLab deploy token and
# configuring Kubernetes registry pull secret via Terraform.
#
# Run this AFTER:
#   1. GitLab project is created
#   2. Terraform cluster is running (terraform apply done)
#
# Usage: bash scripts/deploy-token-setup.sh
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

GREEN='\033[32m'; CYAN='\033[36m'; AMBER='\033[33m'; RESET='\033[0m'

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════${RESET}"
echo -e "${CYAN}  GitLab Deploy Token Setup Helper${RESET}"
echo -e "${CYAN}═══════════════════════════════════════════════════════${RESET}"
echo ""
echo "This script will guide you through:"
echo "  1. Creating a GitLab deploy token (manual — browser required)"
echo "  2. Storing credentials in .envrc"
echo "  3. Creating the K8s image pull secret via Terraform"
echo ""

# ─── Step 1: Browser instructions ────────────────────────────────────────────
echo -e "${CYAN}── Step 1: Create deploy token in GitLab ──────────────${RESET}"
echo ""
echo "  1. Open your GitLab project in browser"
echo "  2. Go to: Settings → Repository → Deploy tokens"
echo "  3. Click 'Add new token'"
echo "  4. Fill in:"
echo "       Name:   k8s-image-pull"
echo "       Expiry: $(date -v+90d '+%Y-%m-%d' 2>/dev/null || date -d '+90 days' '+%Y-%m-%d' 2>/dev/null || echo 'set 90 days from today')"
echo "       Scope:  ✅ read_registry  (ONLY this one)"
echo "  5. Click 'Create deploy token'"
echo "  6. COPY BOTH username and password — shown only once!"
echo ""
read -p "Press Enter when you have the token credentials ready..."

# ─── Step 2: Collect credentials ─────────────────────────────────────────────
echo ""
echo -e "${CYAN}── Step 2: Enter your deploy token credentials ─────────${RESET}"
echo ""
read -rp "  Deploy token username: " DEPLOY_USERNAME
read -rsp "  Deploy token password: " DEPLOY_PASSWORD
echo ""

if [ -z "$DEPLOY_USERNAME" ] || [ -z "$DEPLOY_PASSWORD" ]; then
  echo -e "${AMBER}⚠️  Username or password empty — aborting${RESET}"
  exit 1
fi

# ─── Step 3: Update .envrc ────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}── Step 3: Updating .envrc ─────────────────────────────${RESET}"

if [ ! -f ".envrc" ]; then
  cp scripts/envrc.template .envrc
fi

# Replace placeholders
sed -i.bak \
  "s|DEPLOY_TOKEN_USERNAME|${DEPLOY_USERNAME}|g; \
   s|DEPLOY_TOKEN_PASSWORD|${DEPLOY_PASSWORD}|g" \
  .envrc
rm -f .envrc.bak

echo -e "  ${GREEN}✅ .envrc updated with deploy token credentials${RESET}"
echo ""

# ─── Step 4: Source and apply ─────────────────────────────────────────────────
echo -e "${CYAN}── Step 4: Applying to Kubernetes ──────────────────────${RESET}"
echo ""
echo "  Sourcing .envrc and running terraform apply..."
echo ""

# shellcheck source=/dev/null
source .envrc

cd terraform
terraform apply \
  -target=module.k8s_app.kubernetes_secret.registry_auth \
  -auto-approve

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}  ✅ Deploy token configured!${RESET}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${RESET}"
echo ""
echo "  The K8s image pull secret has been created."
echo "  Your CI/CD pipeline can now pull images from GitLab registry."
echo ""
echo -e "${CYAN}  Next: Set KUBE_CONFIG in GitLab CI/CD variables:${RESET}"
echo "  make export-kubeconfig"
echo ""
