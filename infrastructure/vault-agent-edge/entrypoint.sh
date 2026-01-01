#!/bin/sh
# Edge Vault Agent entrypoint script
# Initializes Edge AppRole credentials

set -e

echo "Initializing Edge Vault Agent..."

# Create certificate directory
mkdir -p /vault/certs

# Write Edge AppRole credentials from environment variables
echo "$EDGE_VAULT_ROLE_ID" > /tmp/role-id
echo "$EDGE_VAULT_SECRET_ID" > /tmp/secret-id

# Set proper permissions
chmod 600 /tmp/role-id /tmp/secret-id

echo "Starting Edge Vault Agent with configuration at /vault/config/agent.hcl"

# Execute vault agent with provided arguments
exec vault "$@"
