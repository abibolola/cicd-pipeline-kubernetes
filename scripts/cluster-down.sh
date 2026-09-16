#!/usr/bin/env bash
# Destroy the cluster. The resource group is KEPT so the service principal
# role assignment survives between sessions.
# Run at the END of every session. Push to git first.
set -euo pipefail

RG="${RG:-rg-shortener}"
CLUSTER="${CLUSTER:-aks-shortener}"

if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  echo "!! Uncommitted changes present. Commit and push before destroying."
  git status --short
  read -r -p "Continue anyway? [y/N] " reply
  [[ "${reply}" == "y" ]] || exit 1
fi

echo "==> Deleting cluster '${CLUSTER}'"
az aks delete --resource-group "${RG}" --name "${CLUSTER}" --yes

echo "==> Removing stale kubeconfig entries"
kubectl config delete-context "${CLUSTER}" 2>/dev/null || true
kubectl config delete-cluster "${CLUSTER}" 2>/dev/null || true

echo "==> Remaining resources in ${RG} (should be empty):"
az resource list --resource-group "${RG}" -o table
echo "==> Billing stopped."
