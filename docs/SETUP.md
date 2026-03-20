# SETUP.md — Zero to Running: Complete Setup Guide

> **Target audience:** Anyone cloning this repo from scratch on macOS (Apple Silicon / Intel).  
> **Goal:** Running app at `http://webapp.local` in under 30 minutes.

---

## Prerequisites Checklist

Before you begin, confirm you have:
- [ ] macOS (Apple Silicon M1/M2/M3 or Intel)
- [ ] Admin access (for `sudo` commands)
- [ ] Internet connection
- [ ] ~4 GB free RAM
- [ ] ~10 GB free disk space

---

## Phase 1 — Install System Tools

### 1.1 Homebrew (macOS package manager)

```bash
# Check if already installed
brew --version

# If not installed:
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Apple Silicon only — add brew to PATH:
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zshrc
source ~/.zshrc
```

### 1.2 Git

```bash
# Check if installed
git --version

# Install if missing
brew install git

# Configure your identity (required for commits)
git config --global user.name  "Your Name"
git config --global user.email "your@email.com"

# Verify
git config --global --list
```

### 1.3 OrbStack (Docker runtime — replaces Docker Desktop)

```bash
# Install OrbStack
brew install --cask orbstack

# Launch OrbStack (first time — opens a small menu-bar app)
open -a OrbStack

# Wait ~30 seconds for it to start, then verify Docker CLI works:
docker version
docker run --rm hello-world
```

> **Why OrbStack?** It is faster and lighter than Docker Desktop on Apple Silicon,
> uses less RAM, and provides the exact same `docker` CLI interface.
> The reviewer needs only OrbStack installed to reproduce everything.

### 1.4 Terraform

```bash
# Check if already installed (you mentioned it is)
terraform version

# If you need to install or upgrade:
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# Verify
terraform version
# Expected: Terraform v1.7.x or higher
```

### 1.5 Kind (Kubernetes in Docker)

```bash
brew install kind

# Verify
kind version
# Expected: kind v0.22.x or higher
```

### 1.6 kubectl (Kubernetes CLI)

```bash
brew install kubectl

# Verify
kubectl version --client
```

### 1.7 Helm (Kubernetes package manager)

```bash
brew install helm

# Verify
helm version
```

### 1.8 ngrok (public URL for reviewer)

```bash
brew install ngrok/ngrok/ngrok

# Sign up free at https://ngrok.com → copy your authtoken
ngrok config add-authtoken YOUR_TOKEN_HERE

# Verify
ngrok version
```

### Final check — all tools installed

```bash
echo "=== Tool Versions ===" && \
git --version && \
docker version --format '{{.Client.Version}}' && \
terraform version | head -1 && \
kind version && \
kubectl version --client --short && \
helm version --short && \
ngrok version
```

---

## Phase 2 — GitLab Account Setup

### 2.1 Create GitLab account

1. Go to [https://gitlab.com/users/sign_up](https://gitlab.com/users/sign_up)
2. Create a free account
3. Confirm your email

### 2.2 Add SSH key to GitLab

```bash
# Generate SSH key (if you don't have one)
ssh-keygen -t ed25519 -C "your@email.com" -f ~/.ssh/id_ed25519

# Copy public key to clipboard
cat ~/.ssh/id_ed25519.pub | pbcopy
```

4. Go to GitLab → **Profile** → **SSH Keys** → paste and save
5. Test:
```bash
ssh -T git@gitlab.com
# Expected: Welcome to GitLab, @yourusername!
```

### 2.3 Create a new GitLab project

1. Click **New project** → **Create blank project**
2. Name it: `react-k8s-terraform-demo`
3. Set to **Private**
4. Uncheck "Initialize repository with README" (we'll push our own)
5. Click **Create project**

---

## Phase 3 — Push Code to GitLab

### 3.1 Clone this repository and set remote

```bash
# Navigate to where you want the project
cd ~/projects  # or wherever you prefer

# Clone YOUR new GitLab repo (empty)
git clone git@gitlab.com:YOUR_USERNAME/react-k8s-terraform-demo.git
cd react-k8s-terraform-demo

# Copy all project files into this folder
# (or if you downloaded the zip, extract it here)
```

If you downloaded this project as a zip:

```bash
cd react-k8s-terraform-demo
git init
git remote add origin git@gitlab.com:YOUR_USERNAME/react-k8s-terraform-demo.git
git add .
git commit -m "feat: initial project setup — Terraform + React + GitLab CI"
git push -u origin main
```

---

## Phase 4 — Configure GitLab CI/CD Variables

These are secrets that the CI/CD pipeline needs. They are **never** stored in code.

1. Go to your GitLab project → **Settings** → **CI/CD** → **Variables** → **Expand**
2. Add the following variables:

| Key | Value | Type | Protected | Masked |
|-----|-------|------|-----------|--------|
| `KUBE_CONFIG` | *(see step 4.2 below)* | Variable | ✅ | ✅ |

> **Note:** `CI_REGISTRY_USER` and `CI_REGISTRY_PASSWORD` are automatically provided by
> GitLab for the Container Registry — you do **not** need to add these manually.

### 4.2 Generate KUBE_CONFIG value

After running Terraform (Phase 5), encode your kubeconfig:

```bash
# Run this after terraform apply (Phase 5)
cat kubeconfig | base64 | tr -d '\n' | pbcopy
# Paste the clipboard value as the KUBE_CONFIG variable in GitLab
```

---

## Phase 5 — Provision Kubernetes Cluster with Terraform

```bash
cd terraform

# Copy and edit variables
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
cluster_name       = "react-k8s-cluster"
kubernetes_version = "v1.29.2"
app_name           = "react-app"
namespace          = "webapp"
image_repository   = "registry.gitlab.com/YOUR_USERNAME/react-k8s-terraform-demo/react-app"
image_tag          = "latest"
replicas           = 2
```

Set sensitive variables via environment (never in tfvars file):

```bash
export TF_VAR_grafana_admin_password="YourSecurePassword123"
export TF_VAR_registry_username="deploy-token-username"   # set after step 6.1
export TF_VAR_registry_password="deploy-token-password"   # set after step 6.1
```

Initialise and apply:

```bash
terraform init

# Preview what will be created
terraform plan

# Create everything (~5 minutes)
terraform apply
# Type 'yes' when prompted
```

Expected output:
```
Apply complete! Resources: 12 added, 0 changed, 0 destroyed.

Outputs:
  cluster_name    = "react-k8s-cluster"
  kubeconfig_path = "/path/to/kubeconfig"
  app_url         = "http://webapp.local"
  grafana_url     = "http://localhost:3000"
```

### Verify cluster is healthy

```bash
export KUBECONFIG=../kubeconfig

kubectl get nodes
# NAME                           STATUS   ROLES           AGE
# react-k8s-cluster-control-plane   Ready    control-plane   2m
# react-k8s-cluster-worker          Ready    <none>          2m

kubectl get pods -A
# All pods should be Running or Completed
```

---

## Phase 6 — GitLab Deploy Token (for K8s image pull)

### 6.1 Create a deploy token

1. GitLab project → **Settings** → **Repository** → **Deploy tokens**
2. Click **Add token**:
   - Name: `k8s-image-pull`
   - Expiry: set 90 days from today
   - Scopes: ✅ `read_registry` only
3. Click **Create deploy token**
4. **Copy both username and password immediately** (shown only once)

```bash
# Set these and re-run terraform apply to create the K8s pull secret
export TF_VAR_registry_username="YOUR_DEPLOY_TOKEN_USERNAME"
export TF_VAR_registry_password="YOUR_DEPLOY_TOKEN_PASSWORD"
terraform apply
```

### 6.2 Add KUBE_CONFIG to GitLab CI/CD

```bash
# Encode kubeconfig (run from project root)
cat kubeconfig | base64 | tr -d '\n' | pbcopy
```

Go to **Settings → CI/CD → Variables** → add `KUBE_CONFIG` (protected + masked).

---

## Phase 7 — Local DNS Setup

```bash
# Add local hostnames (required to access app via browser)
echo "127.0.0.1 webapp.local" | sudo tee -a /etc/hosts
echo "127.0.0.1 grafana.local" | sudo tee -a /etc/hosts

# Verify
ping -c1 webapp.local
```

---

## Phase 8 — Trigger CI/CD Pipeline

```bash
# Push any change to trigger the pipeline
git add .
git commit -m "feat: trigger initial deployment"
git push origin main
```

Watch the pipeline:
1. GitLab → your project → **CI/CD** → **Pipelines**
2. Click the running pipeline to watch live logs
3. All stages should go green ✅

---

## Phase 9 — Verify Everything Works

```bash
# 1. Check pods are running
kubectl get pods -n webapp

# 2. Check ingress
kubectl get ingress -n webapp

# 3. Open the app
open http://webapp.local

# 4. Open Grafana
open http://grafana.local
# Login: admin / (your TF_VAR_grafana_admin_password)
```

---

## Phase 10 — Share with Reviewer via ngrok

```bash
# Expose the local app publicly
ngrok http 80

# Output example:
# Forwarding  https://abc123.ngrok-free.app -> http://localhost:80
#
# Share the https://abc123.ngrok-free.app URL with the reviewer
```

> **Note:** The ngrok URL is temporary. For the reviewer session, keep ngrok running.

---

## Cleanup

When you are done with the task:

```bash
# Destroy all Kubernetes resources and the cluster
cd terraform
terraform destroy

# Stop OrbStack (optional)
# Right-click OrbStack in menu bar → Quit

# Remove local DNS entries
sudo sed -i '' '/webapp.local/d' /etc/hosts
sudo sed -i '' '/grafana.local/d' /etc/hosts
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `docker: command not found` | Restart terminal after OrbStack install |
| `kind: cluster already exists` | `kind delete cluster --name react-k8s-cluster` |
| `terraform apply` timeout | Re-run `terraform apply` — Kind cluster creation can be slow |
| Ingress not reachable | Wait 60s after cluster creation for ingress controller to start |
| Pipeline fails at deploy | Check KUBE_CONFIG variable is set and correctly base64 encoded |
| Image pull errors | Verify deploy token has `read_registry` scope |

---

*For detailed architecture decisions, see [ARCHITECTURE.md](ARCHITECTURE.md)*  
*For security posture, see [SECURITY.md](SECURITY.md)*  
*For day-2 operations, see [RUNBOOK.md](RUNBOOK.md)*

---

## Important: Terraform vs CI/CD Ownership

Understanding what each tool manages prevents confusion:

| Resource | Managed By | Why |
|----------|-----------|-----|
| Kind cluster | Terraform | Infrastructure — stable, rarely changes |
| Namespace | Terraform | Infrastructure |
| Service, Ingress, HPA, PDB | Terraform | Infrastructure |
| ServiceAccount + Pull Secret | Terraform | Infrastructure |
| Nginx Ingress Controller | Terraform (Helm) | Shared cluster service |
| Prometheus + Grafana | Terraform (Helm) | Shared cluster service |
| **Deployment** | **GitLab CI/CD** | Changes every commit — owns the image |

**Why the Deployment is NOT in Terraform:**

Terraform runs **before** CI/CD has pushed any image. If Terraform created
the Deployment, it would reference an image that doesn't exist yet → pods
would be in `ImagePullBackOff` immediately.

The solution: Terraform creates everything except the Deployment. The first
CI/CD pipeline run creates the Deployment via `kubectl apply`. This is called
the **infra/app split** and is standard in production GitOps setups.

**First-time sequence:**

```
make tf-apply          → cluster + namespace + service + ingress + monitoring
                          (no Deployment yet — that's OK)
git push origin main   → triggers pipeline → builds image → pushes to registry
                          → kubectl apply kubernetes/deployment.yaml
                          → Deployment created for the first time ✅
```

