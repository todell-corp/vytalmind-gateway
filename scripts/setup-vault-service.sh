#!/usr/bin/env bash
set -euo pipefail

# Usage: setup-vault-service.sh <service-name> <common-name> [alt-names] [ttl]
if [[ $# -lt 2 ]]; then
  cat <<EOF
Usage: setup-vault-service.sh <service-name> <common-name> [alt-names] [ttl]

Arguments:
  service-name  - Service identifier (e.g., keycloak, api-gateway)
  common-name   - Primary domain (e.g., keycloak.odell.com)
  alt-names     - Comma-separated alt names (default: service-name,localhost)
  ttl           - Certificate TTL (default: 168h)

Example:
  setup-vault-service.sh keycloak keycloak.odell.com "keycloak,localhost" 168h
EOF
  exit 1
fi

SERVICE="$1"
COMMON_NAME="$2"

ALT_NAMES="${3:-${COMMON_NAME},localhost}"
# Normalize alt names: remove duplicates, keep order stable
ALT_NAMES=$(echo "${ALT_NAMES}" | tr ',' '\n' | sort -u | paste -sd, -)

TTL="${4:-168h}"

VAULT_ADDR="${VAULT_ADDR:-https://vault.odell.com:8200}"
PKI_PATH="pki-intermediate"
ROLE_NAME="${SERVICE}"
POLICY_NAME="vault-agent-${SERVICE}"

echo "==> Setting up Vault PKI role and policy for service: ${SERVICE}"
echo "    Common Name: ${COMMON_NAME}"
echo "    Alt Names: ${ALT_NAMES}"
echo "    TTL: ${TTL}"
echo ""

# Check Vault connection
if ! vault status >/dev/null 2>&1; then
  echo "❌ Error: Cannot connect to Vault at ${VAULT_ADDR}"
  echo "   Make sure VAULT_ADDR and VAULT_TOKEN are set correctly"
  exit 1
fi

echo "✓ Connected to Vault"

# Create or update PKI role (idempotent)
echo "==> Creating/updating PKI role: ${ROLE_NAME}"
# Extract base domain (e.g., keycloak.odell.com -> odell.com)
BASE_DOMAIN=$(echo "${COMMON_NAME}" | awk -F. '{print $(NF-1)"."$NF}')

vault write "${PKI_PATH}/roles/${ROLE_NAME}" \
  allowed_domains="${BASE_DOMAIN}" \
  allow_bare_domains=false \
  allow_subdomains=true \
  allow_localhost=true \
  max_ttl="${TTL}" \
  ttl="${TTL}" \
  key_type="rsa" \
  key_bits=2048

echo "✓ PKI role created/updated"

# Create policy for the service (idempotent)
echo "==> Creating/updating policy: ${POLICY_NAME}"
cat <<EOF | vault policy write "${POLICY_NAME}" -
# Policy for ${SERVICE} service certificate issuance

# Allow reading the CA certificate
path "${PKI_PATH}/cert/ca" {
  capabilities = ["read"]
}

# Allow issuing certificates for ${SERVICE}
path "${PKI_PATH}/issue/${ROLE_NAME}" {
  capabilities = ["create", "update"]
}

# Allow reading root CA
path "pki-root/cert/ca" {
  capabilities = ["read"]
}
EOF

echo "✓ Policy created/updated"

# Check if AppRole already exists for this service
echo "==> Checking AppRole: ${SERVICE}"
if vault read "auth/approle/role/${SERVICE}" >/dev/null 2>&1; then
  echo "==> AppRole '${SERVICE}' already exists, updating policies"
  # Get existing policies
  EXISTING_POLICIES=$(vault read -field=token_policies "auth/approle/role/${SERVICE}" 2>/dev/null || echo "")

  # Check if our policy is already in the list
  if echo "${EXISTING_POLICIES}" | grep -q "${POLICY_NAME}"; then
    echo "✓ Policy '${POLICY_NAME}' already attached to AppRole"
  else
    # Append our policy to existing ones
    if [ -n "${EXISTING_POLICIES}" ]; then
      NEW_POLICIES="${EXISTING_POLICIES},${POLICY_NAME}"
    else
      NEW_POLICIES="${POLICY_NAME}"
    fi
    vault write "auth/approle/role/${SERVICE}" \
      token_policies="${NEW_POLICIES}" \
      token_ttl=24h \
      token_max_ttl=768h
    echo "✓ AppRole updated with policy '${POLICY_NAME}'"
  fi
else
  echo "==> Creating AppRole: ${SERVICE}"
  vault write "auth/approle/role/${SERVICE}" \
    token_policies="${POLICY_NAME}" \
    token_ttl=24h \
    token_max_ttl=768h
  echo "✓ AppRole created"
fi

# Validate certificate issuance
echo ""
echo "==> Validating certificate issuance for ${SERVICE}"

vault write "${PKI_PATH}/issue/${ROLE_NAME}" \
  common_name="${COMMON_NAME}" \
  alt_names="${ALT_NAMES}" \
  ttl="1h" >/dev/null

echo "✓ Certificate issuance verified"