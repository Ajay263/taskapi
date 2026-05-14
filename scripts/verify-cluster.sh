#!/bin/bash
PASS=0; FAIL=0

echo "╔══════════════════════════════════════╗"
echo "║   Cluster Health Check               ║"
echo "╚══════════════════════════════════════╝"

check() {
  local name="$1"; local cmd="$2"
  eval "$cmd" > /dev/null 2>&1 && \
    { echo "  ✅  $name"; PASS=$((PASS+1)); } || \
    { echo "  ❌  $name"; FAIL=$((FAIL+1)); }
}

check "kubectl can reach cluster" "kubectl cluster-info"
check "control-plane node Ready" \
  "kubectl get node taskapi-local-control-plane --no-headers | grep -q ' Ready '"
check "worker node 1 Ready" \
  "kubectl get nodes --no-headers | grep worker | sed -n '1p' | grep -q ' Ready '"
check "worker node 2 Ready" \
  "kubectl get nodes --no-headers | grep worker | sed -n '2p' | grep -q ' Ready '"
check "CoreDNS running" \
  "kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers | grep -q Running"
check "NGINX Ingress Controller running" \
  "kubectl get pods -n ingress-nginx --no-headers | grep -q Running"
check "Metrics Server running" \
  "kubectl get pods -n kube-system -l k8s-app=metrics-server --no-headers | grep -q Running"
check "workload=app node exists" \
  "kubectl get nodes -l workload=app --no-headers | grep -q worker"
check "workload=infra node exists" \
  "kubectl get nodes -l workload=infra --no-headers | grep -q worker"

echo ""
kubectl get nodes --no-headers | awk '{printf "  %-50s %s\n", $1, $2}'
echo ""
echo "  Results: $PASS ✅   $FAIL ❌"
[ $FAIL -eq 0 ] && echo "  🟢 Cluster healthy — proceed to Phase 4" || \
  { echo "  🔴 $FAIL checks failed"; exit 1; }