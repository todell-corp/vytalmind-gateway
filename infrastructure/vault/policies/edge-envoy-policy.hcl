# Vault Policy for Edge Envoy
# Allows edge proxy to issue TLS certificates

# Read/write access to PKI for TLS certificates
path "pki/issue/edge-gateway" {
  capabilities = ["create", "update"]
}

# Read CA certificate
path "pki/cert/ca" {
  capabilities = ["read"]
}

# Renew own token
path "auth/token/renew-self" {
  capabilities = ["update"]
}
