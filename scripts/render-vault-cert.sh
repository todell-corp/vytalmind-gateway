#!/usr/bin/env bash
set -euo pipefail

# Usage: render-vault-cert.sh <service-name> <json-path> [reload-cmd]
if [[ $# -lt 2 ]]; then
  echo "Usage: render-vault-cert.sh <service-name> <json-path> [reload-cmd]"
  exit 1
fi

SERVICE="$1"
JSON="$2"
RELOAD_CMD="${3:-}"

CERT_DIR="/vault/certs"

LEAF="${CERT_DIR}/${SERVICE}.leaf.pem"
ISSUING_CA="${CERT_DIR}/${SERVICE}.issuing_ca.pem"
FULLCHAIN="${CERT_DIR}/${SERVICE}.fullchain.pem"
KEY="${CERT_DIR}/${SERVICE}.key"

# Extract certificate components from JSON
jq -r '.certificate'  "$JSON" > "$LEAF"
jq -r '.issuing_ca'   "$JSON" > "$ISSUING_CA"
jq -r '.private_key'  "$JSON" > "$KEY"

# Create fullchain (leaf + issuing CA)
cat "$LEAF" "$ISSUING_CA" > "$FULLCHAIN"

# Secure private key
chmod 600 "$KEY"

echo "[vault-agent] Rendered certs for $SERVICE"

# Optional reload command
if [[ -n "$RELOAD_CMD" ]]; then
  echo "[vault-agent] Running reload command for $SERVICE"
  eval "$RELOAD_CMD" || true
fi
