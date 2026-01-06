#!/bin/bash
set -e

# Generate OAuth2 secret files from environment variables
# Usage: ./generate-oauth-secrets.sh

SECRETS_DIR="${SECRETS_DIR:-/etc/envoy/secrets}"

echo "Generating OAuth2 secrets in ${SECRETS_DIR}..."

# Generate token secret
envsubst < /tmp/token-secret.yaml.template > "${SECRETS_DIR}/token-secret.yaml"
echo "Generated ${SECRETS_DIR}/token-secret.yaml"

# Generate HMAC secret
envsubst < /tmp/hmac-secret.yaml.template > "${SECRETS_DIR}/hmac-secret.yaml"
echo "Generated ${SECRETS_DIR}/hmac-secret.yaml"

echo "OAuth2 secrets generated successfully"
