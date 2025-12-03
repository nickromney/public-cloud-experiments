#!/usr/bin/env bash
set -euo pipefail
GITEA_ADMIN_USER="gitea-admin"
GITEA_ADMIN_PASS="ChangeMe123!"
GITEA_HTTP="https://localhost:3000"

echo "Fetching keys..."
keys=$(curl -sk -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASS}" "${GITEA_HTTP}/api/v1/user/keys")
echo "Keys: $keys"

# Find ID of 'seed-key'
id=$(echo "$keys" | python3 -c "import sys, json; print(next((k['id'] for k in json.load(sys.stdin) if k['title'] == 'seed-key'), ''))")

if [ -n "$id" ]; then
  echo "Deleting old seed-key (ID: $id)..."
  curl -sk -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASS}" -X DELETE "${GITEA_HTTP}/api/v1/user/keys/$id"
  echo "Deleted."
else
  echo "seed-key not found."
fi
