# Vault Policy for Internal Envoy
# Allows internal proxy to issue mTLS certificates from intermediate PKI

# Issue mTLS certificates from intermediate PKI
path "pki-intermediate/issue/internal-services" {
  capabilities = ["create", "update"]
}

# Read intermediate CA
path "pki-intermediate/cert/ca" {
  capabilities = ["read"]
}

# Read root CA
path "pki-root/cert/ca" {
  capabilities = ["read"]
}

# Renew token
path "auth/token/renew-self" {
  capabilities = ["update"]
}
