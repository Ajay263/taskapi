#!/bin/bash
set -euo pipefail
# set -e  → exit immediately if any command fails
# set -u  → treat unset variables as errors (catches typos like $VAUL_TOKEN)
# set -o pipefail → a pipe fails if any command in it fails

echo "╔══════════════════════════════════════╗"
echo "║   DevOps Environment Setup           ║"
echo "╚══════════════════════════════════════╝"

# ── ArgoCD CLI ──────────────────────────────────────────────────────────────
# We need this CLI to log into ArgoCD and trigger syncs from the terminal
echo "→ Installing ArgoCD CLI..."
curl -sSL -o /usr/local/bin/argocd \
  https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd

# ── HashiCorp Vault CLI ──────────────────────────────────────────────────────
# We use this to configure Vault: create secrets, policies, and auth roles
echo "→ Installing Vault CLI..."
VAULT_VERSION="1.15.6"
curl -sSL -o /tmp/vault.zip \
  "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip"
cd /tmp && unzip -o vault.zip && mv vault /usr/local/bin/vault
chmod +x /usr/local/bin/vault

# ── Kustomize ──────────────────────────────────────────────────────────────
# Kubernetes manifest overlay tool — patches YAML per environment
echo "→ Installing Kustomize..."
curl -sSL "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" \
  | bash -s -- /usr/local/bin

# ── istioctl ──────────────────────────────────────────────────────────────
# Istio CLI — installs the service mesh and checks its status
echo "→ Installing istioctl..."
curl -sSL https://istio.io/downloadIstio | ISTIO_VERSION=1.20.3 sh -
mv /root/istio-1.20.3/bin/istioctl /usr/local/bin/ 2>/dev/null || \
  mv /home/vscode/istio-1.20.3/bin/istioctl /usr/local/bin/ 2>/dev/null || \
  find / -name istioctl -type f 2>/dev/null | head -1 | xargs -I{} mv {} /usr/local/bin/

# ── Trivy ──────────────────────────────────────────────────────────────────
# Security scanner: finds CVEs in container images and misconfigs in YAML
echo "→ Installing Trivy..."
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends wget gnupg apt-transport-https
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | \
  gpg --dearmor | sudo tee /usr/share/keyrings/trivy.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" | \
  sudo tee /etc/apt/sources.list.d/trivy.list
sudo apt-get update -qq && sudo apt-get install -y trivy

# ── yq ──────────────────────────────────────────────────────────────────────
# YAML processor — used in CI scripts to edit YAML values programmatically
echo "→ Installing yq..."
wget -qO /usr/local/bin/yq \
  https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
chmod +x /usr/local/bin/yq

# ── jq ──────────────────────────────────────────────────────────────────────
echo "→ Installing jq..."
sudo apt-get install -y jq

echo ""
echo "╔══════════════════════════════════════╗"
echo "║   ✅ Setup complete!                 ║"
echo "║   Run: bash .devcontainer/verify-tools.sh"
echo "╚══════════════════════════════════════╝"