# Vault Policy for Edge Envoy
# Allows edge proxy to issue TLS certificates

# Read/write access to PKI for TLS certificates
path "pki-edge/issue/edge-gateway" {
  capabilities = ["create", "update"]
}

# Read edge CA certificate
path "pki-edge/cert/ca" {
  capabilities = ["read"]
}

# Read intermediate CA certificate (for Apicurio certificates)
path "pki-intermediate/cert/ca" {
  capabilities = ["read"]
}

# Read root CA certificate
path "pki-root/cert/ca" {
  capabilities = ["read"]
}

# Issue internal services certificates (for Apicurio)
path "pki-intermediate/issue/internal-services" {
  capabilities = ["create", "update"]
}

# Renew own token
path "auth/token/renew-self" {
  capabilities = ["update"]
}
