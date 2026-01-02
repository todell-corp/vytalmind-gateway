#!/bin/bash
# Setup Vault PKI engines for TLS and mTLS certificates
# Run this script once to configure your existing Vault at https://vault.odell.com:8200
#
# Prerequisites:
#   - Vault CLI installed (brew install vault)
#   - VAULT_TOKEN environment variable set with admin privileges
#   - Network access to vault.odell.com:8200
#
# Usage:
#   export VAULT_TOKEN=<your-vault-admin-token>
#   ./infrastructure/vault/scripts/setup-pki.sh

set -e

echo "=========================================="
echo "VytalMind Gateway - Vault PKI Setup"
echo "=========================================="
echo ""

# Check prerequisites
if ! command -v vault &> /dev/null; then
    echo "❌ ERROR: Vault CLI is not installed"
    echo "   Install with: brew install vault"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "❌ ERROR: jq is not installed"
    echo "   Install with: brew install jq"
    exit 1
fi

if [ -z "$VAULT_TOKEN" ]; then
    echo "❌ ERROR: VAULT_TOKEN environment variable is not set"
    echo ""
    echo "Please set your Vault admin token:"
    echo "  export VAULT_TOKEN=<your-vault-admin-token>"
    echo ""
    exit 1
fi

export VAULT_ADDR="https://vault.odell.com:8200"

echo "Vault Address: ${VAULT_ADDR}"
echo ""

# Test Vault connectivity
echo "🔍 Testing Vault connectivity..."
if ! vault status &> /dev/null; then
    echo "❌ ERROR: Cannot connect to Vault at ${VAULT_ADDR}"
    echo "   Please check:"
    echo "   1. Network connectivity to vault.odell.com"
    echo "   2. Vault is running and accessible"
    echo "   3. Port 8200 is open"
    exit 1
fi
echo "✅ Vault is reachable"
echo ""

# Authenticate
echo "🔐 Authenticating with Vault..."
if ! vault login ${VAULT_TOKEN} &> /dev/null; then
    echo "❌ ERROR: Authentication failed"
    echo "   Please check your VAULT_TOKEN is valid and has admin privileges"
    exit 1
fi
echo "✅ Authentication successful"
echo ""

# Enable root PKI engine for edge TLS certificates
echo "📦 Configuring Root PKI Engine (Edge TLS Certificates)..."
vault secrets enable -path=pki pki 2>/dev/null || echo "   ℹ️  PKI already enabled, skipping..."

# Configure root PKI
vault secrets tune -max-lease-ttl=87600h pki

# Generate root CA (only if not exists)
if ! vault read pki/cert/ca &> /dev/null; then
    echo "   Creating Root CA..."
    vault write -field=certificate pki/root/generate/internal \
      common_name="VytalMind Root CA" \
      ttl=87600h > /tmp/root-ca.crt
    echo "   ✅ Root CA created"
else
    echo "   ℹ️  Root CA already exists, skipping generation"
fi

# Configure CA and CRL URLs
vault write pki/config/urls \
  issuing_certificates="https://vault.odell.com:8200/v1/pki/ca" \
  crl_distribution_points="https://vault.odell.com:8200/v1/pki/crl"

# Create role for edge gateway TLS certificates
echo "   Creating edge-gateway role..."
vault write pki/roles/edge-gateway \
  allowed_domains="vytalmind.local,localhost,odell.com" \
  allow_subdomains=true \
  allow_localhost=true \
  allow_ip_sans=true \
  max_ttl="8760h" \
  require_cn=false

echo "✅ Root PKI configured"
echo ""

# Enable intermediate PKI for internal mTLS
echo "📦 Configuring Intermediate PKI Engine (Internal mTLS)..."
vault secrets enable -path=pki_int pki 2>/dev/null || echo "   ℹ️  Intermediate PKI already enabled, skipping..."

vault secrets tune -max-lease-ttl=43800h pki_int

# Check if intermediate CA already exists
if ! vault read pki_int/cert/ca &> /dev/null; then
    echo "   Creating Intermediate CA..."

    # Generate intermediate CSR
    vault write -format=json pki_int/intermediate/generate/internal \
      common_name="VytalMind Intermediate CA" \
      ttl=43800h | jq -r '.data.csr' > /tmp/pki_intermediate.csr

    # Sign intermediate certificate with root CA
    vault write -format=json pki/root/sign-intermediate \
      csr=@/tmp/pki_intermediate.csr \
      format=pem_bundle \
      ttl=43800h | jq -r '.data.certificate' > /tmp/intermediate.cert.pem

    # Import signed certificate
    vault write pki_int/intermediate/set-signed \
      certificate=@/tmp/intermediate.cert.pem

    echo "   ✅ Intermediate CA created and signed"
else
    echo "   ℹ️  Intermediate CA already exists, skipping generation"
fi

# Configure intermediate PKI URLs
vault write pki_int/config/urls \
  issuing_certificates="https://vault.odell.com:8200/v1/pki_int/ca" \
  crl_distribution_points="https://vault.odell.com:8200/v1/pki_int/crl"

# Create role for internal services (mTLS)
echo "   Creating internal-service role..."
vault write pki_int/roles/internal-service \
  allowed_domains="vytalmind.local,odell.com" \
  allow_subdomains=true \
  max_ttl="720h" \
  require_cn=true \
  allowed_uri_sans="spiffe://vytalmind.local/service/*" \
  server_flag=true \
  client_flag=true

echo "✅ Intermediate PKI configured"
echo ""

# Create policies
echo "🔒 Creating Vault Policies..."
vault policy write edge-envoy - <<EOF
# Vault Policy for Edge Envoy
path "pki/issue/edge-gateway" {
  capabilities = ["create", "update"]
}
path "pki/cert/ca" {
  capabilities = ["read"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
EOF
echo "   ✅ edge-envoy policy created"

vault policy write internal-envoy - <<EOF
# Vault Policy for Internal Envoy
path "pki_int/issue/internal-service" {
  capabilities = ["create", "update"]
}
path "pki_int/cert/ca" {
  capabilities = ["read"]
}
path "pki/cert/ca" {
  capabilities = ["read"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
EOF
echo "   ✅ internal-envoy policy created"
echo ""

# Enable AppRole auth method
echo "🔑 Configuring AppRole Authentication..."
vault auth enable approle 2>/dev/null || echo "   ℹ️  AppRole already enabled, skipping..."

# Create AppRole for edge-envoy
echo "   Creating edge-envoy AppRole..."
vault write auth/approle/role/edge-envoy \
  token_policies="edge-envoy" \
  token_ttl=1h \
  token_max_ttl=24h \
  secret_id_ttl=0 \
  secret_id_num_uses=0

# Get edge-envoy AppRole credentials
EDGE_ROLE_ID=$(vault read -field=role_id auth/approle/role/edge-envoy/role-id)
EDGE_SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/edge-envoy/secret-id)

# Create AppRole for internal-envoy
echo "   Creating internal-envoy AppRole..."
vault write auth/approle/role/internal-envoy \
  token_policies="internal-envoy" \
  token_ttl=1h \
  token_max_ttl=24h \
  secret_id_ttl=0 \
  secret_id_num_uses=0

# Get internal-envoy AppRole credentials
INTERNAL_ROLE_ID=$(vault read -field=role_id auth/approle/role/internal-envoy/role-id)
INTERNAL_SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/internal-envoy/secret-id)

echo "✅ AppRole authentication configured"
echo ""

# Clean up temp files
rm -f /tmp/root-ca.crt /tmp/pki_intermediate.csr /tmp/intermediate.cert.pem

# Display results
echo ""
echo "=========================================="
echo "✅ SETUP COMPLETE!"
echo "=========================================="
echo ""
echo "📋 AppRole Credentials Generated:"
echo ""
echo "Edge Envoy:"
echo "  EDGE_VAULT_ROLE_ID=${EDGE_ROLE_ID}"
echo "  EDGE_VAULT_SECRET_ID=${EDGE_SECRET_ID}"
echo ""
echo "Internal Envoy:"
echo "  INTERNAL_VAULT_ROLE_ID=${INTERNAL_ROLE_ID}"
echo "  INTERNAL_VAULT_SECRET_ID=${INTERNAL_SECRET_ID}"
echo ""
echo "=========================================="
echo "📝 NEXT STEPS:"
echo "=========================================="
echo ""
echo "1. Copy these credentials to your .env file:"
echo ""
echo "   cp .env.example .env"
echo "   nano .env"
echo ""
echo "2. Add these lines to .env:"
echo ""
echo "VAULT_ADDR=https://vault.odell.com:8200"
echo "EDGE_VAULT_ROLE_ID=${EDGE_ROLE_ID}"
echo "EDGE_VAULT_SECRET_ID=${EDGE_SECRET_ID}"
echo "INTERNAL_VAULT_ROLE_ID=${INTERNAL_ROLE_ID}"
echo "INTERNAL_VAULT_SECRET_ID=${INTERNAL_SECRET_ID}"
echo ""
echo "3. Start the gateway:"
echo ""
echo "   make setup"
echo ""
echo "=========================================="
echo ""
