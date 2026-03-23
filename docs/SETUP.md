# SETUP.md — Zero to Running: Complete Setup Guide

> **Target audience:** Anyone running this repo from scratch on macOS (Apple Silicon).
> **Goal:** Running app at `http://webapp.local` + public URL in under 45 minutes.

---

## Prerequisites Checklist

- [ ] macOS (Apple Silicon M1/M2/M3)
- [ ] Admin access (for `sudo` commands)
- [ ] Internet connection
- [ ] ~8 GB free RAM (4GB for GitLab CE VM + 4GB for cluster)
- [ ] ~20 GB free disk space

---

## Phase 1 — Install System Tools

### 1.1 Homebrew
```bash
brew --version || \
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Apple Silicon — add to PATH if needed
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zshrc && source ~/.zshrc
```

### 1.2 Core tools
```bash
brew install git kubectl helm direnv
brew install --cask orbstack

# Add direnv hook to shell
echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc
source ~/.zshrc
```

### 1.3 Terraform
```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

terraform version
# Expected: Terraform v1.7.x or higher
```

### 1.4 ngrok
```bash
brew install ngrok/ngrok/ngrok

# Sign up free at https://ngrok.com — copy authtoken from dashboard
ngrok config add-authtoken YOUR_TOKEN_HERE
```

> **Note:** Kind CLI is NOT required. The Terraform `tehcyx/kind` provider
> manages the cluster directly via Docker — no `kind` binary needed.

### 1.5 Verify all tools
```bash
for tool in git docker terraform kubectl helm ngrok direnv; do
  command -v $tool && echo "✅ $tool" || echo "❌ $tool missing"
done
```

---

## Phase 2 — GitLab CE on Multipass VM

GitLab CE runs on a local Ubuntu VM managed by Multipass. This provides a
self-hosted Git server, Container Registry, CI/CD pipelines, and Terraform
HTTP remote state backend — all on your laptop.

### 2.1 Install Multipass
```bash
brew install --cask multipass
multipass version
```

### 2.2 Create the GitLab CE VM
```bash
multipass launch --name gitlab-ce \
  --cpus 2 \
  --memory 4G \
  --disk 20G \
  24.04

multipass list
# Expected: gitlab-ce  Running  192.168.x.x
```

### 2.3 Install GitLab CE
```bash
multipass exec gitlab-ce -- bash << 'EOF'
sudo apt-get update -y
sudo apt-get install -y curl openssh-server ca-certificates tzdata
curl -fsSL https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | sudo bash
sudo EXTERNAL_URL="http://$(hostname -I | awk '{print $1}')" apt-get install -y gitlab-ce

# Add 4GB swap (required on 4GB RAM VM)
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
EOF
```

Wait ~5 minutes, then verify:
```bash
multipass exec gitlab-ce -- sudo gitlab-ctl status
```

### 2.4 Get initial root password
```bash
multipass exec gitlab-ce -- \
  sudo cat /etc/gitlab/initial_root_password | grep Password:
```

Open `http://192.168.2.2` → login as `root` → set new password → create your user.

### 2.5 Fix GitLab CE registry HSTS

GitLab CE enables HSTS on the registry by default — this breaks Docker HTTP access.
Run this after every `gitlab-ctl reconfigure`:
```bash
make fix-registry
```

### 2.6 Create GitLab project

1. GitLab → **New project** → **Create blank project**
2. Name: `react-k8s-terraform-demo`
3. Visibility: **Private**
4. Uncheck "Initialize with README"

### 2.7 Add SSH key
```bash
ssh-keygen -t ed25519 -C "your@email.com" -f ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub | pbcopy
```

GitLab → **Profile** → **SSH Keys** → paste and save.
```bash
# Test connection
ssh -T git@192.168.2.2 -o StrictHostKeyChecking=no
# Expected: Welcome to GitLab, @yourusername!
```

---

## Phase 3 — Clone and Push Code
```bash
cd ~/Desktop
git clone git@192.168.2.2:YOUR_USERNAME/react-k8s-terraform-demo.git
cd react-k8s-terraform-demo
git add .
git commit -m "feat: initial project setup"
git push -u origin main
```

---

## Phase 4 — Configure Secrets and Environment

### 4.1 Create .envrc from template
```bash
cp scripts/envrc.template .envrc
```

Edit `.envrc` with your values:
```bash
export TF_VAR_grafana_admin_password="YourSecurePassword123"
export TF_VAR_registry_username="k8s-deploy-token"    # set after Phase 6
export TF_VAR_registry_password="your-deploy-token"   # set after Phase 6
export TF_HTTP_USERNAME="your-gitlab-username"
export TF_HTTP_PASSWORD="your-personal-access-token"  # GitLab → Profile → Access Tokens
export KUBECONFIG="/Users/YOUR_USERNAME/Desktop/react-k8s-terraform-demo/kubeconfig"
export HELM_REPOSITORY_CACHE="$HOME/Desktop/react-k8s-terraform-demo/.helm-cache"
export HELM_REPOSITORY_CONFIG="$HOME/Desktop/react-k8s-terraform-demo/.helm-repositories.yaml"
```
```bash
direnv allow .
# Expected: ✅ Environment loaded — TF_VAR_* variables set
```

### 4.2 Configure Terraform backend
```bash
cp terraform/backend.hcl.example terraform/backend.hcl
```

Edit `terraform/backend.hcl`:
```hcl
address        = "http://192.168.2.2/api/v4/projects/YOUR_PROJECT_ID/terraform/state/react-k8s-terraform-demo"
lock_address   = "http://192.168.2.2/api/v4/projects/YOUR_PROJECT_ID/terraform/state/react-k8s-terraform-demo/lock"
unlock_address = "http://192.168.2.2/api/v4/projects/YOUR_PROJECT_ID/terraform/state/react-k8s-terraform-demo/lock"
lock_method    = "POST"
unlock_method  = "DELETE"
retry_wait_min = 5
```

> Find your project ID: GitLab → project page → **Settings** → **General** → Project ID.

---

## Phase 5 — Provision Kubernetes Cluster with Terraform

### 5.1 Configure tfvars
```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform/terraform.tfvars`:
```hcl
cluster_name             = "react-k8s-cluster"
kubernetes_version       = "v1.32.0"
app_name                 = "react-app"
namespace                = "webapp"
ingress_host             = "webapp.local"
enable_catch_all_ingress = true
image_repository         = "192.168.2.2:5050/YOUR_USERNAME/react-k8s-terraform-demo/react-app"
replicas                 = 2
registry_host            = "192.168.2.2:5050"
```

### 5.2 Initialise and apply
```bash
cd terraform
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
# Type 'yes' when prompted — takes ~5 minutes
```

Expected output:
```
Apply complete! Resources: 13 added, 0 changed, 0 destroyed.

Outputs:
  app_url      = "http://webapp.local"
  cluster_name = "react-k8s-cluster"
  grafana_url  = "http://grafana.local"
```

### 5.3 Verify cluster
```bash
kubectl get nodes
# react-k8s-cluster-control-plane   Ready   control-plane
# react-k8s-cluster-worker           Ready   <none>

kubectl get pods -A
# All pods Running or Completed
```

---

## Phase 6 — GitLab Deploy Token

1. GitLab project → **Settings** → **Repository** → **Deploy tokens**
2. Click **Add token**:
   - Name: `k8s-deploy-token`
   - Expiry: 90 days from today
   - Scopes: ✅ `read_registry` only
3. **Copy username and password immediately** (shown only once)
```bash
# Update .envrc with the token values, then re-apply
direnv allow .
cd terraform && terraform apply
```

---

## Phase 7 — GitLab CI/CD Variables

1. GitLab project → **Settings** → **CI/CD** → **Variables** → **Expand**
2. Add:

| Key | Protected | Masked |
|-----|-----------|--------|
| `KUBE_CONFIG` | ✅ | ✅ |

Generate value:
```bash
cat kubeconfig | base64 | tr -d '\n' | pbcopy
# Paste clipboard as KUBE_CONFIG value in GitLab
```

> `CI_REGISTRY_USER` and `CI_REGISTRY_PASSWORD` are provided automatically — do NOT add them.

---

## Phase 8 — Local DNS Setup
```bash
echo "127.0.0.1 webapp.local grafana.local" | sudo tee -a /etc/hosts
ping -c1 webapp.local
```

---

## Phase 9 — Register GitLab Runner
```bash
brew install gitlab-runner
brew services start gitlab-runner

# Get runner token: GitLab → Settings → CI/CD → Runners → New project runner
gitlab-runner register \
  --url http://192.168.2.2 \
  --token YOUR_RUNNER_TOKEN \
  --executor shell \
  --name mac-shell-runner \
  --non-interactive
```

---

## Phase 10 — Trigger CI/CD Pipeline
```bash
git commit --allow-empty -m "ci: trigger initial deployment"
git push origin main
```

Watch: GitLab → project → **CI/CD** → **Pipelines**

All 4 stages green: `test:build` → `docker:build-push` → `deploy:kubernetes`

---

## Phase 11 — Verify Everything
```bash
bash scripts/validate.sh
# ✅ ALL CHECKS PASSED — ready to share!

open http://webapp.local
open http://grafana.local   # admin / your grafana password
```

---

## Phase 12 — Public Access via ngrok

ngrok runs as a permanent launchd service — starts automatically on login, no terminal needed.
```bash
# ngrok.yml already configured with static domain
# Just load the launchd service:
launchctl load ~/Library/LaunchAgents/com.ngrok.react-k8s.plist

# Verify tunnel
curl -s http://localhost:4040/api/tunnels | python3 -c "
import json,sys
for t in json.load(sys.stdin)['tunnels']:
    print(t['name'], '->', t['public_url'])
"
```

Public URL: **https://mervin-tetrahydric-dwayne.ngrok-free.dev**

---

## Teardown — Complete Cleanup
```bash
# 1. Destroy Kubernetes infrastructure
cd terraform && terraform destroy

# 2. Stop ngrok launchd service
launchctl unload ~/Library/LaunchAgents/com.ngrok.react-k8s.plist
rm ~/Library/LaunchAgents/com.ngrok.react-k8s.plist

# 3. Stop and unregister GitLab runner
brew services stop gitlab-runner
gitlab-runner unregister --all-runners

# 4. Remove GitLab CE VM
multipass delete gitlab-ce && multipass purge

# 5. Remove DNS entries
sudo sed -i '' '/webapp.local/d' /etc/hosts
sudo sed -i '' '/grafana.local/d' /etc/hosts

# 6. Uninstall tools (optional)
brew uninstall gitlab-runner helm ngrok terraform direnv
brew uninstall --cask orbstack multipass

# 7. Remove project files
rm -rf ~/Desktop/react-k8s-terraform-demo

# 8. Remove Docker registry credentials
docker logout 192.168.2.2:5050
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `docker: command not found` | Restart terminal after OrbStack install |
| `terraform apply` timeout | Re-run `terraform apply` — Kind creation can be slow |
| Ingress not reachable | Wait 60s after apply for Traefik to start |
| Pipeline fails at docker login | Run `make fix-registry` — GitLab CE HSTS issue |
| Image pull errors in K8s | Verify deploy token has `read_registry` scope |
| Pipeline fails at deploy | Check KUBE_CONFIG is set, protected + masked |
| `direnv: command not found` | Run `source ~/.zshrc` after installing direnv |
| ngrok shows wrong URL | Check `cat ~/Library/Application\ Support/ngrok/ngrok.yml` |

---

## Terraform vs CI/CD Ownership

| Resource | Managed By | Why |
|----------|-----------|-----|
| Kind cluster | Terraform | Infrastructure — stable |
| Namespace, SA, pull secret | Terraform | Infrastructure |
| Service, Ingress, HPA, PDB | Terraform | Infrastructure |
| Traefik v3 | Terraform (Helm) | Shared cluster service |
| Prometheus + Grafana | Terraform (Helm) | Shared cluster service |
| **Deployment** | **GitLab CI/CD** | Changes every commit |

**Why Deployment is NOT in Terraform:** Terraform runs before CI has pushed any image.
If Terraform created the Deployment, pods would be in `ImagePullBackOff` immediately.
CI creates the Deployment on the first pipeline run.
```
make tf-apply        → cluster + infrastructure (no Deployment yet)
git push → main      → pipeline builds image → kubectl apply → Deployment created ✅
```

---

*See [ARCHITECTURE.md](ARCHITECTURE.md) for deep-dive architecture decisions*
*See [SECURITY.md](SECURITY.md) for full security posture*
*See [REVIEWER.md](REVIEWER.md) for task compliance evidence*
