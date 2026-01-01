# Vault Policy for Vault Agent
# Allows agent to issue certificates for both Edge and Internal Envoy

# Edge TLS certificates from edge PKI
path "pki-edge/issue/edge-gateway" {
  capabilities = ["create", "update"]
}

path "pki-edge/cert/ca" {
  capabilities = ["read"]
}

# Internal mTLS certificates from intermediate PKI
path "pki-intermediate/issue/internal-services" {
  capabilities = ["create", "update", "read"]
}

path "pki-intermediate/cert/ca" {
  capabilities = ["read"]
}

# Token renewal
path "auth/token/renew-self" {
  capabilities = ["update"]
}
