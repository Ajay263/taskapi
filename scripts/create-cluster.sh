#!/bin/bash
set -euo pipefail

CLUSTER_NAME="taskapi-local"

echo "╔══════════════════════════════════════╗"
echo "║   Creating KinD Kubernetes Cluster   ║"
echo "╚══════════════════════════════════════╝"

# Step 1: Verify Docker is running
echo "→ Checking Docker..."
if ! docker info > /dev/null 2>&1; then
  echo "  ❌ Docker not running."
  echo "     Fix: sudo service docker start"
  exit 1
fi
echo "  ✅ Docker is running"

# Step 2: Skip creation if cluster already exists (makes script idempotent)
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "  ℹ️  Cluster '${CLUSTER_NAME}' already exists — skipping creation"
else
  cat > /tmp/kind-config.yaml << 'KINDEOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: taskapi-local

nodes:
  # ── Control Plane ──────────────────────────────────────────────────────
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      # hostPorts shifted by +1 to avoid conflict with devcontainer forwardPorts
      - containerPort: 30080   # TaskAPI NodePort
        hostPort: 8081         # devcontainer owns 8080
        protocol: TCP
      - containerPort: 30443   # ArgoCD NodePort
        hostPort: 8444         # devcontainer owns 8443
        protocol: TCP
      - containerPort: 30090   # Prometheus NodePort
        hostPort: 9091         # devcontainer owns 9090
        protocol: TCP
      - containerPort: 30030   # Grafana NodePort
        hostPort: 3001         # devcontainer owns 3000
        protocol: TCP
      - containerPort: 30200   # Vault NodePort
        hostPort: 8201         # devcontainer owns 8200
        protocol: TCP
      - containerPort: 30686   # Jaeger NodePort
        hostPort: 16687        # devcontainer owns 16686
        protocol: TCP

  # ── Worker 1: Application workloads ───────────────────────────────────
  - role: worker
    labels:
      workload: app

  # ── Worker 2: Infrastructure workloads ────────────────────────────────
  - role: worker
    labels:
      workload: infra

networking:
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/12"
  disableDefaultCNI: false
KINDEOF

  echo "→ Creating cluster (3–5 minutes)..."
  kind create cluster --config /tmp/kind-config.yaml --wait 300s
fi

# Step 3: Verify basic connectivity
echo ""
echo "→ Verifying cluster..."
kubectl cluster-info
echo ""
echo "→ Nodes:"
kubectl get nodes -o wide

# Step 4: Wait for system pods
echo ""
echo "→ Waiting for system pods to be ready..."
kubectl wait --for=condition=ready pod \
  --all --namespace=kube-system --timeout=180s
echo "  ✅ System pods ready"

# Step 5: Install NGINX Ingress Controller
echo ""
echo "→ Installing NGINX Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

echo "→ Waiting for NGINX Ingress Controller..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
echo "  ✅ NGINX Ingress Controller ready"

# Step 6: Install Metrics Server
echo ""
echo "→ Installing Metrics Server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

kubectl patch deployment metrics-server -n kube-system --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-",
        "value":"--kubelet-insecure-tls"}]'

kubectl wait --for=condition=available deployment/metrics-server \
  --namespace=kube-system --timeout=120s
echo "  ✅ Metrics Server ready"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║   ✅ Cluster is ready!               ║"
echo "║   Run: bash scripts/verify-cluster.sh"
echo "╚══════════════════════════════════════╝"