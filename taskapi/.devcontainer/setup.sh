#!/bin/bash
set -euo pipefail

echo "╔══════════════════════════════════════╗"
echo "║   DevOps Environment Setup           ║"
echo "╚══════════════════════════════════════╝"

# ── ArgoCD CLI ──────────────────────────────────────────────────────────────
echo "→ Installing ArgoCD CLI..."
curl -sSL -o /tmp/argocd \
  https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /tmp/argocd
sudo mv /tmp/argocd /usr/local/bin/argocd

# ── HashiCorp Vault CLI ──────────────────────────────────────────────────────
echo "→ Installing Vault CLI..."
VAULT_VERSION="1.15.6"
curl -sSL -o /tmp/vault.zip \
  "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip"
cd /tmp && unzip -o vault.zip
chmod +x /tmp/vault
sudo mv /tmp/vault /usr/local/bin/vault

# ── Kustomize ──────────────────────────────────────────────────────────────
echo "→ Installing Kustomize..."
curl -sSL "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" \
  | bash -s -- /tmp
sudo mv /tmp/kustomize /usr/local/bin/kustomize

# ── istioctl ──────────────────────────────────────────────────────────────
# Use a pinned direct tarball download — avoids the installer's unpredictable
# working-directory behaviour inside devcontainers
echo "→ Installing istioctl..."
ISTIO_VERSION="1.20.3"
curl -sSL \
  "https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istioctl-${ISTIO_VERSION}-linux-amd64.tar.gz" \
  | tar -xz -C /tmp istioctl
chmod +x /tmp/istioctl
sudo mv /tmp/istioctl /usr/local/bin/istioctl

# ── Trivy ──────────────────────────────────────────────────────────────────
# Official install script — avoids apt repo GPG issues common in devcontainers
echo "→ Installing Trivy..."
curl -sSfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
  | sudo sh -s -- -b /usr/local/bin

# ── yq ──────────────────────────────────────────────────────────────────────
# Pin to a known release rather than "latest" to avoid redirect/name changes
echo "→ Installing yq..."
YQ_VERSION="v4.44.1"
curl -sSL -o /tmp/yq \
  "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64"
chmod +x /tmp/yq
sudo mv /tmp/yq /usr/local/bin/yq

# ── jq ──────────────────────────────────────────────────────────────────────
echo "→ Installing jq..."
sudo apt-get install -y jq

echo ""
echo "╔══════════════════════════════════════╗"
echo "║   ✅ Setup complete!                 ║"
echo "║   Run: bash .devcontainer/verify-tools.sh"
echo "╚══════════════════════════════════════╝"