#!/bin/bash
set -e

echo "=========================================="
echo "  DevOps Environment Setup"
echo "=========================================="

# Install additional tools
echo "→ Installing tools..."

# ArgoCD CLI
curl -sSL -o /usr/local/bin/argocd \
  https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd

# Vault CLI
VAULT_VERSION="1.15.6"
curl -sSL -o /tmp/vault.zip \
  https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip
unzip -o /tmp/vault.zip -d /usr/local/bin
chmod +x /usr/local/bin/vault

# Kustomize
curl -sSL "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
mv kustomize /usr/local/bin/

# Istioctl
curl -sSL https://istio.io/downloadIstio | ISTIO_VERSION=1.20.0 sh -
mv istio-1.20.0/bin/istioctl /usr/local/bin/

# Trivy (security scanner)
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | \
  gpg --dearmor | sudo tee /usr/share/keyrings/trivy.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" | \
  sudo tee -a /etc/apt/sources.list.d/trivy.list
sudo apt-get update -qq && sudo apt-get install -y trivy

# kubesec (Kubernetes security scanner)
wget -q https://github.com/controlplaneio/kubesec/releases/latest/download/kubesec_linux_amd64.tar.gz
tar -xzf kubesec_linux_amd64.tar.gz
mv kubesec /usr/local/bin/

# kube-bench (CIS benchmarks)
curl -sSL https://github.com/aquasecurity/kube-bench/releases/latest/download/kube-bench_linux_amd64.tar.gz | \
  tar -xzC /usr/local/bin kube-bench

# yq (YAML processor)
wget -qO /usr/local/bin/yq \
  https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
chmod +x /usr/local/bin/yq

echo "→ All tools installed!"
echo ""
echo "Run 'bash scripts/create-cluster.sh' to create your KinD cluster"