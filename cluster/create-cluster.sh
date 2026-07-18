#!/usr/bin/env bash

set -Eeuo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-devops-demo}"
K3S_IMAGE="${K3S_IMAGE:-rancher/k3s:v1.35.5-k3s1}"
API_PORT="${API_PORT:-6550}"
HTTP_PORT="${HTTP_PORT:-8080}"

required_commands=(
  docker
  k3d
  kubectl
)

for command_name in "${required_commands[@]}"; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command is missing: ${command_name}" >&2
    exit 1
  fi
done

if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon is unavailable." >&2
  echo "Start Docker Desktop and verify WSL Integration." >&2
  exit 1
fi

cluster_exists="$(
  k3d cluster list 2>/dev/null \
    | awk 'NR > 1 {print $1}' \
    | grep -Fx "${CLUSTER_NAME}" \
    || true
)"

if [[ -n "${cluster_exists}" ]]; then
  echo "Cluster '${CLUSTER_NAME}' already exists."
else
  echo "Creating cluster '${CLUSTER_NAME}'..."

  k3d cluster create "${CLUSTER_NAME}" \
    --servers 1 \
    --agents 2 \
    --image "${K3S_IMAGE}" \
    --api-port "127.0.0.1:${API_PORT}" \
    --port "${HTTP_PORT}:80@loadbalancer" \
    --wait \
    --timeout 240s
fi

kubectl config use-context "k3d-${CLUSTER_NAME}"

echo "Waiting for all Kubernetes nodes..."
kubectl wait \
  --for=condition=Ready \
  nodes \
  --all \
  --timeout=240s

for worker_index in 0 1; do
  kubectl label node \
    "k3d-${CLUSTER_NAME}-agent-${worker_index}" \
    node-role.kubernetes.io/worker=true \
    --overwrite
done

echo
echo "Current context:"
kubectl config current-context

echo
echo "Kubernetes nodes:"
kubectl get nodes -o wide

echo
echo "Storage classes:"
kubectl get storageclass

echo
echo "Ingress classes:"
kubectl get ingressclass

echo
echo "Cluster '${CLUSTER_NAME}' is ready."
echo "Future frontend URL: http://localhost:${HTTP_PORT}"
