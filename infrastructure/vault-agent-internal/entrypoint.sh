#!/bin/sh
# Internal Vault Agent entrypoint script
# Initializes Internal AppRole credentials

set -e

echo "Initializing Internal Vault Agent..."

# Create certificate directory
mkdir -p /vault/certs

# Write Internal AppRole credentials from environment variables
echo "$INTERNAL_VAULT_ROLE_ID" > /tmp/role-id
echo "$INTERNAL_VAULT_SECRET_ID" > /tmp/secret-id

# Set proper permissions
chmod 600 /tmp/role-id /tmp/secret-id

echo "Starting Internal Vault Agent with configuration at /vault/config/agent.hcl"

# Execute vault agent with provided arguments
exec vault "$@"
