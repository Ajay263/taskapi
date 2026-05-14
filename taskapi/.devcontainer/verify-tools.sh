#!/bin/bash
PASS=0; FAIL=0

echo "╔══════════════════════════════════════╗"
echo "║   Tool Version Check                 ║"
echo "╚══════════════════════════════════════╝"

check_tool() {
  local name="$1"
  local cmd="$2"
  local result
  result=$(eval "$cmd" 2>/dev/null)
  if [ $? -eq 0 ] && [ -n "$result" ]; then
    echo "  ✅  $name: $result"
    PASS=$((PASS+1))
  else
    echo "  ❌  $name: NOT FOUND"
    FAIL=$((FAIL+1))
  fi
}

check_tool "docker"    "docker --version | awk '{print \$3}' | tr -d ','"
check_tool "kubectl"   "kubectl version --client -o json 2>/dev/null | jq -r '.clientVersion.gitVersion'"
check_tool "kind"      "kind version | awk '{print \$2}'"
check_tool "helm"      "helm version --short | tr -d 'v' | cut -d'+' -f1"
check_tool "kustomize" "kustomize version"
check_tool "argocd"    "argocd version --client 2>/dev/null | head -1 | awk '{print \$2}'"
check_tool "vault"     "vault version | awk '{print \$2}'"
check_tool "istioctl"  "istioctl version --remote=false 2>/dev/null | head -1"
check_tool "trivy"     "trivy --version | head -1 | awk '{print \$2}'"
# yq v4 format: "yq (https://github.com/mikefarah/yq/) version v4.x.x"  → field 4
check_tool "yq"        "yq --version 2>/dev/null | awk '{print \$NF}'"
check_tool "python3"   "python3 --version | awk '{print \$2}'"
check_tool "pip"       "pip --version | awk '{print \$2}'"
check_tool "git"       "git --version | awk '{print \$3}'"
check_tool "curl"      "curl --version | head -1 | awk '{print \$2}'"
check_tool "jq"        "jq --version"

echo ""
echo "  Results: $PASS ✅   $FAIL ❌"
if [ $FAIL -eq 0 ]; then
  echo "  🟢 All tools ready — proceed to Phase 3"
else
  echo "  🔴 $FAIL tools missing — re-run: bash .devcontainer/setup.sh"
  exit 1
fi