#!/bin/bash
set -e

CLUSTER_NAME="taskapi-local"

echo "=========================================="
echo "  Creating KinD Cluster: $CLUSTER_NAME"
echo "=========================================="

# KinD cluster config
cat > /tmp/kind-config.yaml <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
nodes:
  # Control plane node
  - role: control-plane
    kubeadmConfigPatches:
    - |
      kind: InitConfiguration
      nodeRegistration:
        kubeletExtraArgs:
          node-labels: "ingress-ready=true"
    extraPortMappings:
    # Map host ports → container ports for NodePort services
    - containerPort: 30080
      hostPort: 8080
      protocol: TCP
    - containerPort: 30443
      hostPort: 8443
      protocol: TCP
    - containerPort: 30090
      hostPort: 9090    # Prometheus
      protocol: TCP
    - containerPort: 30030
      hostPort: 3000    # Grafana
      protocol: TCP
    - containerPort: 30200
      hostPort: 8200    # Vault
      protocol: TCP
  # Worker node 1 (simulates app workloads)
  - role: worker
    labels:
      workload: app
  # Worker node 2 (simulates infra/monitoring workloads)
  - role: worker
    labels:
      workload: infra

# Networking
networking:
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/12"
  disableDefaultCNI: false  # Use kindnet
EOF

# Check if cluster already exists
if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  echo "Cluster '${CLUSTER_NAME}' already exists. Skipping creation."
else
  echo "→ Creating cluster (this takes 2-3 minutes)..."
  kind create cluster --config /tmp/kind-config.yaml --wait 300s
fi

echo ""
echo "→ Cluster created! Nodes:"
kubectl get nodes -o wide

echo ""
echo "→ Installing NGINX Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s

echo ""
echo "✅ Cluster ready!"
echo ""
echo "Next steps:"
echo "  1. Run: bash scripts/install-vault.sh"
echo "  2. Run: bash scripts/install-argocd.sh"
echo "  3. Run: bash scripts/install-monitoring.sh"