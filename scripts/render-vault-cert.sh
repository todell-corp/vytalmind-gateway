#!/bin/sh
set -eu

# Usage: render-vault-cert.sh <service-name> <json-path> [reload-cmd]
if [ $# -lt 2 ]; then
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
SDS="${CERT_DIR}/${SERVICE}-sds.yaml"

# Extract certificate components from JSON using atomic writes (temp + mv)
# This ensures Envoy's inotify/directory watcher fires correctly on Docker overlay fs
jq -r '.certificate' "$JSON" > "${LEAF}.tmp" && mv "${LEAF}.tmp" "$LEAF"
jq -r '.issuing_ca' "$JSON" > "${ISSUING_CA}.tmp" && mv "${ISSUING_CA}.tmp" "$ISSUING_CA"
jq -r '.private_key' "$JSON" > "${KEY}.tmp"
chmod 600 "${KEY}.tmp"
mv "${KEY}.tmp" "$KEY"

# Create fullchain (leaf + issuing CA) atomically
cat "$LEAF" "$ISSUING_CA" > "${FULLCHAIN}.tmp" && mv "${FULLCHAIN}.tmp" "$FULLCHAIN"

# Create SDS configuration for Envoy automatic cert reload
# Note: Paths must be from Envoy's perspective (/etc/envoy/certs)
# Atomic write ensures Envoy's watched_directory sees IN_MOVED_TO event
cat > "${SDS}.tmp" <<EOF
resources:
  - "@type": type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.Secret
    name: ${SERVICE}_cert
    tls_certificate:
      certificate_chain:
        filename: /etc/envoy/certs/${SERVICE}.fullchain.pem
      private_key:
        filename: /etc/envoy/certs/${SERVICE}.key
EOF
mv "${SDS}.tmp" "$SDS"

echo "[vault-agent] Rendered certs for $SERVICE"

# Optional reload command
if [ -n "$RELOAD_CMD" ]; then
  echo "[vault-agent] Running reload command for $SERVICE"
  eval "$RELOAD_CMD" || true
fi
