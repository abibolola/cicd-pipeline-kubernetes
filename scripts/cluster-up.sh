#!/usr/bin/env bash
# Create the ephemeral AKS cluster inside the persistent resource group.
# Run at the START of a working session. Takes ~5 minutes.
set -euo pipefail

RG="${RG:-rg-shortener}"
CLUSTER="${CLUSTER:-aks-shortener}"
LOCATION="${LOCATION:-australiaeast}"
NODE_COUNT="${NODE_COUNT:-2}"
NODE_SIZE="${NODE_SIZE:-Standard_B2s_v2}"

echo "==> Creating AKS cluster '${CLUSTER}' in '${RG}'"
az aks create \
  --resource-group "${RG}" \
  --name "${CLUSTER}" \
  --location "${LOCATION}" \
  --node-count "${NODE_COUNT}" \
  --node-vm-size "${NODE_SIZE}" \
  --load-balancer-sku standard \
  --generate-ssh-keys

echo "==> Fetching credentials"
az aks get-credentials \
  --resource-group "${RG}" \
  --name "${CLUSTER}" \
  --overwrite-existing

kubectl get nodes -o wide
echo "==> Cluster ready. Billing has started."
