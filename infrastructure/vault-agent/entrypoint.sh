#!/bin/sh
# Vault Agent entrypoint script
# Writes AppRole credentials from environment variables to files

set -e

echo "Initializing Vault Agent..."

# Create certificate directories
mkdir -p /vault/certs/edge /vault/certs/internal

# Write Edge AppRole credentials to files
echo "$EDGE_VAULT_ROLE_ID" > /vault/config/edge-role-id
echo "$EDGE_VAULT_SECRET_ID" > /vault/config/edge-secret-id

# Write Internal AppRole credentials to files
echo "$INTERNAL_VAULT_ROLE_ID" > /vault/config/internal-role-id
echo "$INTERNAL_VAULT_SECRET_ID" > /vault/config/internal-secret-id

# Set proper permissions
chmod 600 /vault/config/*-role-id /vault/config/*-secret-id

echo "Starting Vault Agent with configuration at /vault/config/agent.hcl"

# Execute vault agent with provided arguments
exec vault "$@"
