#!/usr/bin/env bash
# Build, load into kind, and deploy. Local iteration loop.
set -euo pipefail

CLUSTER="${CLUSTER:-shortener}"
NS="shortener"
TAG="$(git rev-parse --short HEAD 2>/dev/null || echo dev)"
IMAGE="shortener:${TAG}"

echo "==> Building ${IMAGE}"
docker build --build-arg "APP_VERSION=${TAG}" -t "${IMAGE}" .

echo "==> Loading into kind cluster '${CLUSTER}'"
kind load docker-image "${IMAGE}" --name "${CLUSTER}"

echo "==> Namespace and secret"
kubectl apply -f k8s/00-namespace.yaml
kubectl create secret generic shortener-secrets \
  --namespace "${NS}" \
  --from-literal=REDIS_PASSWORD="${REDIS_PASSWORD:-devpassword}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Applying manifests"
for f in k8s/0[134567]-*.yaml; do   #02 and 05 are deliberately skipped
  kubectl apply -f "$f"
done

echo "==> Deployment with image ${IMAGE}"
sed "s|IMAGE_PLACEHOLDER|${IMAGE}|" k8s/05-app-deployment.yaml | kubectl apply -f -

echo "==> Waiting for rollout"
kubectl -n "${NS}" rollout status statefulset/redis --timeout=120s
kubectl -n "${NS}" rollout status deployment/shortener --timeout=120s

echo "==> Done"
kubectl -n "${NS}" get pods -o wide
