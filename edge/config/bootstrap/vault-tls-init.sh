#!/bin/bash
# Bootstrap script for Edge Envoy
# Fetches TLS certificates from Vault using AppRole authentication

set -e

echo "Starting Edge Envoy bootstrap process..."

# Vault configuration
export VAULT_ADDR="${VAULT_ADDR:-https://vault.odell.com:8200}"

# Wait for Vault to be ready
until curl -sk ${VAULT_ADDR}/v1/sys/health > /dev/null 2>&1; do
  echo "Waiting for Vault to be ready..."
  sleep 2
done

echo "Vault is ready, authenticating with AppRole..."

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

# Fetch TLS certificate from Vault
echo "Fetching TLS certificates from Vault PKI..."
CERT_DATA=$(curl -sk --header "X-Vault-Token: ${VAULT_TOKEN}" \
  --request POST \
  --data '{"common_name":"gateway.vytalmind.local","ttl":"8760h","alt_names":"edge-envoy,localhost","ip_sans":"127.0.0.1"}' \
  ${VAULT_ADDR}/v1/pki/issue/edge-gateway)

# Extract certificate, private key, and CA chain
echo "$CERT_DATA" | jq -r '.data.certificate' > /etc/envoy/certs/server.crt
echo "$CERT_DATA" | jq -r '.data.private_key' > /etc/envoy/certs/server.key
echo "$CERT_DATA" | jq -r '.data.ca_chain[]' > /etc/envoy/certs/ca.crt

# Set proper permissions
chmod 600 /etc/envoy/certs/server.key
chmod 644 /etc/envoy/certs/server.crt
chmod 644 /etc/envoy/certs/ca.crt

echo "TLS certificates fetched successfully"

# Get certificate expiration for logging
EXPIRATION=$(echo "$CERT_DATA" | jq -r '.data.expiration')
echo "Certificate expires at: $EXPIRATION"

# Start background certificate renewal process
(
  while true; do
    # Renew certificate 24 hours before expiration (8760h - 24h = 8736h wait)
    # For shorter TTLs, adjust accordingly
    sleep 82800  # 23 hours

    echo "Renewing TLS certificate..."

    # Re-authenticate if needed (tokens expire after 1h by default)
    AUTH_RESPONSE=$(curl -sk --request POST \
      --data "{\"role_id\":\"${VAULT_ROLE_ID}\",\"secret_id\":\"${VAULT_SECRET_ID}\"}" \
      ${VAULT_ADDR}/v1/auth/approle/login)

    VAULT_TOKEN=$(echo $AUTH_RESPONSE | jq -r '.auth.client_token')

    # Fetch new certificate
    CERT_DATA=$(curl -sk --header "X-Vault-Token: ${VAULT_TOKEN}" \
      --request POST \
      --data '{"common_name":"gateway.vytalmind.local","ttl":"8760h","alt_names":"edge-envoy,localhost","ip_sans":"127.0.0.1"}' \
      ${VAULT_ADDR}/v1/pki/issue/edge-gateway)

    echo "$CERT_DATA" | jq -r '.data.certificate' > /etc/envoy/certs/server.crt.new
    echo "$CERT_DATA" | jq -r '.data.private_key' > /etc/envoy/certs/server.key.new
    echo "$CERT_DATA" | jq -r '.data.ca_chain[]' > /etc/envoy/certs/ca.crt.new

    # Atomic replacement
    mv /etc/envoy/certs/server.crt.new /etc/envoy/certs/server.crt
    mv /etc/envoy/certs/server.key.new /etc/envoy/certs/server.key
    mv /etc/envoy/certs/ca.crt.new /etc/envoy/certs/ca.crt

    chmod 600 /etc/envoy/certs/server.key

    echo "Certificate renewed at $(date)"
  done
) &

echo "Starting Envoy..."
exec /usr/local/bin/envoy "$@"
