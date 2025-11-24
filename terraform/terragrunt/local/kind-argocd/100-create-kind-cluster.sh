#!/usr/bin/env bash
#
# Stage 100: Create kind cluster with no CNI
# The cluster will have nodes in NotReady state until Cilium is installed in stage 200
#

set -euo pipefail

# Configuration
CLUSTER_NAME="kind-local"
CONFIG_FILE="./kind-config.yaml"

echo "→ Creating kind cluster '${CLUSTER_NAME}' (5 nodes: 1 control-plane + 4 workers)"
echo "  Note: Nodes will be NotReady until Cilium CNI is installed (stage 200)"

KIND_EXPERIMENTAL_PROVIDER=podman kind create cluster \
  --name "${CLUSTER_NAME}" \
  --config "${CONFIG_FILE}"

echo ""
echo "✓ Cluster created successfully"
echo ""
echo "Cluster info:"
kubectl cluster-info --context "kind-${CLUSTER_NAME}"
echo ""
echo "Nodes (will show NotReady - this is expected):"
kubectl get nodes
echo ""
echo "Current context:"
kubectl config current-context
echo ""
echo "Next: Run stage 200 to install Cilium CNI"
