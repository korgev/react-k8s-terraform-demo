# ─────────────────────────────────────────────────────────────────────────────
# react-k8s-terraform-demo Makefile
# Convenience wrappers for all common operations.
# Run `make help` to see all available commands.
# ─────────────────────────────────────────────────────────────────────────────

# Default shell — use bash for [[ ]] and process substitution
SHELL := /bin/bash

# Project settings (override with: make apply CLUSTER_NAME=my-cluster)
CLUSTER_NAME    ?= react-k8s-cluster
NAMESPACE       ?= webapp
APP_NAME        ?= react-app
KUBECONFIG_PATH ?= ./kubeconfig
TF_DIR          ?= ./terraform
APP_DIR         ?= ./app

# Colours for output
CYAN  := \033[36m
GREEN := \033[32m
AMBER := \033[33m
RED   := \033[31m
RESET := \033[0m

.DEFAULT_GOAL := help

# ─── Help ─────────────────────────────────────────────────────────────────────
.PHONY: help
help: ## Show this help message
	@echo ""
	@echo "  react-k8s-terraform-demo — available commands"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ { \
		printf "  $(CYAN)%-28s$(RESET) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""

# ─── Prerequisites ────────────────────────────────────────────────────────────
.PHONY: check-tools
check-tools: ## Verify all required tools are installed
	@echo -e "$(CYAN)Checking required tools...$(RESET)"
	@for tool in git docker terraform kubectl helm ngrok; do \
		if command -v $$tool &>/dev/null; then \
			echo -e "  $(GREEN)✅ $$tool$(RESET) ($$($$tool version 2>/dev/null | head -1 || echo 'ok'))"; \
		else \
			echo -e "  $(RED)❌ $$tool — not found. See docs/SETUP.md$(RESET)"; \
		fi; \
	done

.PHONY: install-tools
install-tools: ## Install all tools via Homebrew (macOS only)
	@echo -e "$(CYAN)Installing tools via Homebrew...$(RESET)"
	brew install git kubectl helm ngrok/ngrok/ngrok
	brew install --cask orbstack
	@echo -e "$(GREEN)✅ Done. Run 'make check-tools' to verify.$(RESET)"

# ─── Environment Setup ────────────────────────────────────────────────────────
.PHONY: setup-env
setup-env: ## Create .envrc template for TF_VAR_* secrets (direnv compatible)
	@if [ -f .envrc ]; then \
		echo -e "$(AMBER)⚠️  .envrc already exists — not overwriting$(RESET)"; \
	else \
		cp scripts/envrc.template .envrc; \
		echo -e "$(GREEN)✅ .envrc created — edit it and run: source .envrc$(RESET)"; \
	fi

.PHONY: check-env
check-env: ## Check required environment variables are set
	@echo -e "$(CYAN)Checking environment variables...$(RESET)"
	@missing=0; \
	for var in TF_VAR_grafana_admin_password TF_VAR_registry_username TF_VAR_registry_password; do \
		if [ -z "$${!var}" ]; then \
			echo -e "  $(RED)❌ $$var not set$(RESET)"; \
			missing=1; \
		else \
			echo -e "  $(GREEN)✅ $$var is set$(RESET)"; \
		fi; \
	done; \
	[ $$missing -eq 0 ] || (echo -e "\n$(RED)Run: source .envrc$(RESET)" && exit 1)

# ─── Terraform ────────────────────────────────────────────────────────────────
.PHONY: tf-init
tf-init: ## Terraform: initialise providers and modules
	@echo -e "$(CYAN)Initialising Terraform...$(RESET)"
	cd $(TF_DIR) && terraform init -upgrade -backend-config=backend.hcl

.PHONY: tf-plan
tf-plan: check-env ## Terraform: show planned changes
	@echo -e "$(CYAN)Planning Terraform changes...$(RESET)"
	cd $(TF_DIR) && terraform plan

.PHONY: tf-apply
tf-apply: check-env ## Terraform: provision cluster + deploy app + monitoring
	@echo -e "$(CYAN)Applying Terraform (this takes ~5 minutes)...$(RESET)"
	cd $(TF_DIR) && terraform apply
	@echo ""
	@$(MAKE) post-apply

.PHONY: tf-destroy
tf-destroy: ## Terraform: destroy everything (cluster + all resources)
	@echo -e "$(AMBER)⚠️  This will DESTROY the cluster and all resources.$(RESET)"
	@read -p "Type 'yes' to confirm: " confirm && [ "$$confirm" = "yes" ] || exit 1
	cd $(TF_DIR) && terraform destroy

.PHONY: tf-output
tf-output: ## Terraform: show all output values
	cd $(TF_DIR) && terraform output

# ─── Post-apply helpers ───────────────────────────────────────────────────────
.PHONY: post-apply
post-apply: ## Run post-apply steps: DNS + kubeconfig export
	@echo -e "$(CYAN)Post-apply setup...$(RESET)"
	@$(MAKE) add-hosts
	@$(MAKE) export-kubeconfig
	@echo ""
	@echo -e "$(GREEN)✅ All done! Run 'make open' to view the app.$(RESET)"

.PHONY: add-hosts
add-hosts: ## Add webapp.local and grafana.local to /etc/hosts
	@if grep -q "webapp.local" /etc/hosts; then \
		echo -e "  $(AMBER)⚠️  webapp.local already in /etc/hosts$(RESET)"; \
	else \
		echo "127.0.0.1 webapp.local grafana.local" | sudo tee -a /etc/hosts; \
		echo -e "  $(GREEN)✅ Added webapp.local and grafana.local to /etc/hosts$(RESET)"; \
	fi

.PHONY: export-kubeconfig
export-kubeconfig: ## Base64-encode kubeconfig and copy to clipboard (for GitLab CI)
	@if [ -f $(KUBECONFIG_PATH) ]; then \
		cat $(KUBECONFIG_PATH) | base64 | tr -d '\n' | pbcopy; \
		echo -e "  $(GREEN)✅ KUBE_CONFIG (base64) copied to clipboard$(RESET)"; \
		echo -e "  $(CYAN)→ Paste in GitLab: Settings → CI/CD → Variables → KUBE_CONFIG$(RESET)"; \
		echo -e "     (Protected: ✅  Masked: ✅)"; \
	else \
		echo -e "  $(RED)❌ kubeconfig not found at $(KUBECONFIG_PATH)$(RESET)"; \
		echo -e "     Run 'make tf-apply' first"; \
	fi

# ─── Kubernetes ───────────────────────────────────────────────────────────────
.PHONY: k8s-status
k8s-status: ## Show full cluster status (nodes, pods, ingress)
	@export KUBECONFIG=$(KUBECONFIG_PATH); \
	echo -e "\n$(CYAN)─── Nodes ───────────────────────────$(RESET)"; \
	kubectl get nodes -o wide; \
	echo -e "\n$(CYAN)─── App Pods (webapp) ───────────────$(RESET)"; \
	kubectl get pods -n $(NAMESPACE) -o wide; \
	echo -e "\n$(CYAN)─── Ingress ─────────────────────────$(RESET)"; \
	kubectl get ingress -n $(NAMESPACE); \
	echo -e "\n$(CYAN)─── Monitoring Pods ─────────────────$(RESET)"; \
	kubectl get pods -n monitoring; \
	echo -e "\n$(CYAN)─── Ingress Controller ──────────────$(RESET)"; \
	kubectl get pods -n traefik

.PHONY: k8s-logs
k8s-logs: ## Tail logs from the React app pods
	@export KUBECONFIG=$(KUBECONFIG_PATH); \
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(APP_NAME) -f --tail=50

.PHONY: k8s-rollback
k8s-rollback: ## Manually rollback the deployment to previous version
	@export KUBECONFIG=$(KUBECONFIG_PATH); \
	echo -e "$(AMBER)Rolling back $(APP_NAME) in namespace $(NAMESPACE)...$(RESET)"; \
	kubectl rollout undo deployment/$(APP_NAME) -n $(NAMESPACE); \
	kubectl rollout status deployment/$(APP_NAME) -n $(NAMESPACE) --timeout=120s; \
	echo -e "$(GREEN)✅ Rollback complete$(RESET)"

.PHONY: k8s-history
k8s-history: ## Show deployment rollout history
	@export KUBECONFIG=$(KUBECONFIG_PATH); \
	kubectl rollout history deployment/$(APP_NAME) -n $(NAMESPACE)

.PHONY: k8s-describe
k8s-describe: ## Describe the app deployment (good for debugging)
	@export KUBECONFIG=$(KUBECONFIG_PATH); \
	kubectl describe deployment $(APP_NAME) -n $(NAMESPACE)

# ─── App Development ──────────────────────────────────────────────────────────
.PHONY: app-install
app-install: ## Install Node dependencies
	cd $(APP_DIR) && npm ci

.PHONY: app-dev
app-dev: ## Start React dev server (hot reload)
	cd $(APP_DIR) && npm run dev

.PHONY: app-build
app-build: ## Build React app for production
	cd $(APP_DIR) && npm run build

.PHONY: app-docker-build
app-docker-build: ## Build Docker image locally (for testing)
	docker build \
		--build-arg VITE_APP_VERSION=v1.0.0-local \
		--build-arg VITE_COMMIT_SHA=$$(git rev-parse --short HEAD 2>/dev/null || echo "local") \
		--build-arg VITE_BUILD_TIME=$$(date -u +%Y-%m-%dT%H:%M:%SZ) \
		--build-arg VITE_ENVIRONMENT=local \
		-t k8s-webapp:local \
		$(APP_DIR)/
	@echo -e "$(GREEN)✅ Image built: k8s-webapp:local$(RESET)"

.PHONY: app-docker-run
app-docker-run: app-docker-build ## Build and run Docker image locally on port 8080
	docker run --rm -p 8080:8080 k8s-webapp:local &
	@sleep 2 && open http://localhost:8080

# ─── Monitoring ───────────────────────────────────────────────────────────────
.PHONY: grafana
grafana: ## Port-forward Grafana to localhost:3000 (alternative to Ingress)
	@export KUBECONFIG=$(KUBECONFIG_PATH); \
	echo -e "$(CYAN)Opening Grafana at http://localhost:3000 ...$(RESET)"; \
	kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring &
	@sleep 2 && open http://localhost:3000

.PHONY: prometheus
prometheus: ## Port-forward Prometheus to localhost:9090
	@export KUBECONFIG=$(KUBECONFIG_PATH); \
	echo -e "$(CYAN)Opening Prometheus at http://localhost:9090 ...$(RESET)"; \
	kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring &
	@sleep 2 && open http://localhost:9090

# ─── Access ───────────────────────────────────────────────────────────────────
.PHONY: open
open: ## Open app and Grafana in browser
	@open http://webapp.local
	@open http://grafana.local

.PHONY: share
share: ## Print public app URL (ngrok launchd service must be running)
	@echo -e "$(GREEN)Public URL: https://mervin-tetrahydric-dwayne.ngrok-free.dev$(RESET)"
	@open https://mervin-tetrahydric-dwayne.ngrok-free.dev

# ─── Cleanup ──────────────────────────────────────────────────────────────────
.PHONY: clean-cluster
clean-cluster: ## Delete the Kind cluster (keeps Terraform state)
	docker rm -f $(CLUSTER_NAME)-control-plane $(CLUSTER_NAME)-worker 2>/dev/null || true
	docker network rm kind 2>/dev/null || true
	@echo -e "$(GREEN)✅ Cluster deleted$(RESET)"

.PHONY: clean-hosts
clean-hosts: ## Remove webapp.local / grafana.local from /etc/hosts
	sudo sed -i '' '/webapp\.local/d' /etc/hosts
	sudo sed -i '' '/grafana\.local/d' /etc/hosts
	@echo -e "$(GREEN)✅ /etc/hosts cleaned$(RESET)"

.PHONY: clean-all
clean-all: tf-destroy clean-hosts ## Destroy everything + clean /etc/hosts
	@echo -e "$(GREEN)✅ Full cleanup complete$(RESET)"

# ─── Git ──────────────────────────────────────────────────────────────────────
.PHONY: git-setup
git-setup: ## Initialise git and push to GitLab (first time only)
	@if [ -z "$(GITLAB_REMOTE)" ]; then \
		echo -e "$(RED)❌ Set GITLAB_REMOTE first:$(RESET)"; \
		echo -e "   make git-setup GITLAB_REMOTE=git@192.168.2.2:rwx/react-k8s-terraform-demo.git"; \
		exit 1; \
	fi
	git init
	git add .
	git commit -m "feat: initial project — Terraform + React + GitLab CI/CD"
	git remote add origin $(GITLAB_REMOTE)
	git push -u origin main
	@echo -e "$(GREEN)✅ Code pushed to GitLab$(RESET)"

# ─── Full workflow shortcuts ───────────────────────────────────────────────────
.PHONY: up
up: tf-init tf-apply ## Full setup: init + apply (provisions cluster + deploys app)

.PHONY: down
down: clean-all ## Full teardown: destroy cluster + clean DNS

.PHONY: validate
validate: ## Run pre-flight + post-deploy validation checks
	@bash scripts/validate.sh

.PHONY: token-setup
token-setup: ## Interactive guide: create GitLab deploy token + K8s pull secret
	@bash scripts/deploy-token-setup.sh

.PHONY: fix-registry
fix-registry: ## Fix GitLab CE registry HSTS (run after gitlab-ctl reconfigure)
	@echo "Disabling HSTS on GitLab CE registry nginx..."
	@multipass exec gitlab-ce -- sudo sed -i \
		's/add_header Strict-Transport-Security "max-age=63072000";/add_header Strict-Transport-Security "max-age=0";/' \
		/var/opt/gitlab/nginx/conf/service_conf/gitlab-registry.conf
	@multipass exec gitlab-ce -- sudo gitlab-ctl hup nginx
	@echo "✅ Registry HSTS disabled — restart OrbStack if docker login still fails"




