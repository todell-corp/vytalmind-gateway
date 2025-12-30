#!/bin/bash
# Certificate renewal daemon for Internal Envoy
# Renews mTLS certificates before expiration

export VAULT_ADDR="${VAULT_ADDR:-https://vault.odell.com:8200}"

while true; do
  # Renew every 24 days (720h = 30 days TTL, renew 6 days early)
  sleep $((24 * 24 * 3600))

  echo "Renewing mTLS certificates..."

  # Re-authenticate with AppRole
  AUTH_RESPONSE=$(curl -sk --request POST \
    --data "{\"role_id\":\"${VAULT_ROLE_ID}\",\"secret_id\":\"${VAULT_SECRET_ID}\"}" \
    ${VAULT_ADDR}/v1/auth/approle/login)

  VAULT_TOKEN=$(echo $AUTH_RESPONSE | jq -r '.auth.client_token')

  if [ -z "$VAULT_TOKEN" ] || [ "$VAULT_TOKEN" == "null" ]; then
    echo "ERROR: Failed to re-authenticate with Vault for renewal"
    continue
  fi

  # Renew server certificate
  SERVER_CERT=$(curl -sk --header "X-Vault-Token: ${VAULT_TOKEN}" \
    --request POST \
    --data '{"common_name":"internal-envoy.vytalmind.local","ttl":"720h","uri_sans":"spiffe://vytalmind.local/service/internal-envoy"}' \
    ${VAULT_ADDR}/v1/pki_int/issue/internal-service)

  echo "$SERVER_CERT" | jq -r '.data.certificate' > /etc/envoy/certs/server.crt.new
  echo "$SERVER_CERT" | jq -r '.data.private_key' > /etc/envoy/certs/server.key.new

  # Renew client certificate
  CLIENT_CERT=$(curl -sk --header "X-Vault-Token: ${VAULT_TOKEN}" \
    --request POST \
    --data '{"common_name":"internal-envoy-client.vytalmind.local","ttl":"720h","uri_sans":"spiffe://vytalmind.local/service/internal-envoy-client"}' \
    ${VAULT_ADDR}/v1/pki_int/issue/internal-service)

  echo "$CLIENT_CERT" | jq -r '.data.certificate' > /etc/envoy/certs/client.crt.new
  echo "$CLIENT_CERT" | jq -r '.data.private_key' > /etc/envoy/certs/client.key.new

  # Atomic replacement
  mv /etc/envoy/certs/server.crt.new /etc/envoy/certs/server.crt
  mv /etc/envoy/certs/server.key.new /etc/envoy/certs/server.key
  mv /etc/envoy/certs/client.crt.new /etc/envoy/certs/client.crt
  mv /etc/envoy/certs/client.key.new /etc/envoy/certs/client.key

  chmod 600 /etc/envoy/certs/*.key

  echo "Certificates renewed at $(date)"
done
