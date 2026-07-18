#!/usr/bin/env bash

set -Eeuo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-devops-demo}"

if ! command -v k3d >/dev/null 2>&1; then
  echo "Required command is missing: k3d" >&2
  exit 1
fi

cluster_exists="$(
  k3d cluster list 2>/dev/null \
    | awk 'NR > 1 {print $1}' \
    | grep -Fx "${CLUSTER_NAME}" \
    || true
)"

if [[ -n "${cluster_exists}" ]]; then
  echo "Deleting cluster '${CLUSTER_NAME}'..."
  k3d cluster delete "${CLUSTER_NAME}"
else
  echo "Cluster '${CLUSTER_NAME}' does not exist."
fi
