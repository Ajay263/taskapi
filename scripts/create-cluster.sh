#!/bin/bash
set -e

echo "=========================================="
echo "  Creating KinD Cluster"
echo "=========================================="

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
  echo "❌ Docker is not running. Please start Docker first."
  exit 1
fi

# Create cluster config
cat > /tmp/kind-config.yaml <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: taskapi
nodes:
  - role: control-plane
    extraPortMappings:
    - containerPort: 30080
      hostPort: 8080
      protocol: TCP
    - containerPort: 30443
      hostPort: 8443
      protocol: TCP
    - containerPort: 30090
      hostPort: 9090
      protocol: TCP
    - containerPort: 30030
      hostPort: 3000
      protocol: TCP
  - role: worker
  - role: worker
EOF

# Create cluster
if kind get clusters | grep -q "^taskapi$"; then
  echo "→ Cluster 'taskapi' already exists. Skipping creation."
else
  echo "→ Creating cluster (takes 2-3 minutes)..."
  kind create cluster --config /tmp/kind-config.yaml --wait 300s
fi

echo ""
echo "→ Cluster nodes:"
kubectl get nodes

echo ""
echo "✅ KinD cluster is ready!"