#!/bin/bash
# Bootstrap script for Internal Envoy
# Fetches mTLS certificates from Vault PKI using AppRole authentication

set -e

echo "Starting Internal Envoy bootstrap process..."

# Vault configuration
export VAULT_ADDR="${VAULT_ADDR:-https://vault.odell.com:8200}"

# Wait for Vault
until curl -sk ${VAULT_ADDR}/v1/sys/health > /dev/null 2>&1; do
  echo "Waiting for Vault..."
  sleep 2
done

echo "Vault ready, authenticating with AppRole..."

# Authenticate with AppRole to get a token
AUTH_RESPONSE=$(curl -sk --request POST \
  --data "{\"role_id\":\"${VAULT_ROLE_ID}\",\"secret_id\":\"${VAULT_SECRET_ID}\"}" \
  ${VAULT_ADDR}/v1/auth/approle/login)

# Extract the client token
VAULT_TOKEN=$(echo $AUTH_RESPONSE | jq -r '.auth.client_token')

if [ -z "$VAULT_TOKEN" ] || [ "$VAULT_TOKEN" == "null" ]; then
  echo "ERROR: Failed to authenticate with Vault AppRole"
  echo "Response: $AUTH_RESPONSE"
  exit 1
fi

echo "Successfully authenticated with Vault"
export VAULT_TOKEN

echo "Fetching mTLS certificates from Vault PKI..."

# Fetch server certificate (for downstream connections)
SERVER_CERT=$(curl -sk --header "X-Vault-Token: ${VAULT_TOKEN}" \
  --request POST \
  --data '{"common_name":"internal-envoy.vytalmind.local","ttl":"720h","uri_sans":"spiffe://vytalmind.local/service/internal-envoy"}' \
  ${VAULT_ADDR}/v1/pki_int/issue/internal-service)

echo "$SERVER_CERT" | jq -r '.data.certificate' > /etc/envoy/certs/server.crt
echo "$SERVER_CERT" | jq -r '.data.private_key' > /etc/envoy/certs/server.key
echo "$SERVER_CERT" | jq -r '.data.ca_chain[]' > /etc/envoy/certs/ca.crt

# Fetch client certificate (for upstream connections)
CLIENT_CERT=$(curl -sk --header "X-Vault-Token: ${VAULT_TOKEN}" \
  --request POST \
  --data '{"common_name":"internal-envoy-client.vytalmind.local","ttl":"720h","uri_sans":"spiffe://vytalmind.local/service/internal-envoy-client"}' \
  ${VAULT_ADDR}/v1/pki_int/issue/internal-service)

echo "$CLIENT_CERT" | jq -r '.data.certificate' > /etc/envoy/certs/client.crt
echo "$CLIENT_CERT" | jq -r '.data.private_key' > /etc/envoy/certs/client.key

# Set permissions
chmod 600 /etc/envoy/certs/*.key
chmod 644 /etc/envoy/certs/*.crt

echo "mTLS certificates fetched successfully"

# Start certificate renewal daemon
/etc/envoy/config/cert-renewal.sh &

echo "Starting Envoy..."
exec /usr/local/bin/envoy "$@"
