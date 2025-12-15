#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${CERT_MANAGER_NAMESPACE:-cert-manager}"
SECRET_NAME="${MKCERT_CA_SECRET_NAME:-mkcert-ca-key-pair}"

if ! command -v mkcert >/dev/null 2>&1; then
  cat >&2 <<'EOF'
mkcert is required but was not found.

Install on macOS:
  brew install mkcert
  mkcert -install

Then re-run this script.
EOF
  exit 1
fi

CAROOT="$(mkcert -CAROOT)"
CA_CERT="${CAROOT}/rootCA.pem"
CA_KEY="${CAROOT}/rootCA-key.pem"

[[ -f "${CA_CERT}" ]] || { echo "Missing CA cert: ${CA_CERT}" >&2; exit 1; }
[[ -f "${CA_KEY}" ]] || { echo "Missing CA key: ${CA_KEY}" >&2; exit 1; }

kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1 || kubectl create namespace "${NAMESPACE}" >/dev/null

kubectl -n "${NAMESPACE}" create secret tls "${SECRET_NAME}" \
  --cert="${CA_CERT}" \
  --key="${CA_KEY}" \
  --dry-run=client -o yaml \
  | kubectl apply -f -

echo "Created/updated secret ${NAMESPACE}/${SECRET_NAME} from mkcert CA (CAROOT=${CAROOT})."
echo "Next: Argo cert-manager-config should reconcile and issue the dev/uat gateway certs."
