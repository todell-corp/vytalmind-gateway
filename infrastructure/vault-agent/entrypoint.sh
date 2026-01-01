#!/bin/sh
# Vault Agent entrypoint script
# Writes AppRole credentials from environment variables to files

set -e

echo "Initializing Vault Agent..."

# Create certificate directories
mkdir -p /vault/certs/edge /vault/certs/internal

# Write Edge AppRole credentials to /tmp (not mounted volume)
echo "$EDGE_VAULT_ROLE_ID" > /tmp/edge-role-id
echo "$EDGE_VAULT_SECRET_ID" > /tmp/edge-secret-id

# Set proper permissions
chmod 600 /tmp/edge-role-id /tmp/edge-secret-id

echo "Starting Vault Agent with configuration at /vault/config/agent.hcl"

# Execute vault agent with provided arguments
exec vault "$@"
