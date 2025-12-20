#!/usr/bin/env bash
set -euo pipefail

LOGIN_HOST="${1:-login.127.0.0.1.sslip.io}"
TARGET_DNS="${2:-azure-auth-gateway-nginx.azure-auth-gateway.svc.cluster.local}"

COREFILE=$(kubectl -n kube-system get cm coredns -o jsonpath='{.data.Corefile}')

export COREFILE LOGIN_HOST TARGET_DNS

if echo "$COREFILE" | grep -q "factory-dns-rewrite"; then
  echo "CoreDNS already patched (factory-dns-rewrite present)"
  exit 0
fi

PATCHED=$(python3 - <<PY
import os

core = os.environ["COREFILE"]
login = os.environ["LOGIN_HOST"]
target = os.environ["TARGET_DNS"]

insert = (
    "    # factory-dns-rewrite\n"
    f"    rewrite name exact {login} {target}\n"
)

lines = core.splitlines(True)
out = []
inserted = False

for line in lines:
    out.append(line)
    if not inserted and line.strip() == "ready":
        out.append(insert)
        inserted = True

if not inserted:
    out2 = []
    for line in out:
        out2.append(line)
        if not inserted and line.strip() == ".:53 {":
            out2.append(insert)
            inserted = True
    out = out2

if not inserted:
    raise SystemExit("Could not find insertion point in Corefile")

print("".join(out).rstrip("\n") + "\n")
PY
)

# shellcheck disable=SC2001
PATCHED_INDENTED=$(echo "$PATCHED" | sed 's/^/    /')

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |-
$PATCHED_INDENTED
EOF

kubectl -n kube-system rollout restart deployment/coredns
kubectl -n kube-system rollout status deployment/coredns --timeout=120s

echo "Patched CoreDNS rewrite: $LOGIN_HOST -> $TARGET_DNS"
