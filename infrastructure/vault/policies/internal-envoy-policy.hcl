# Vault Policy for Internal Envoy
# Allows internal proxy to issue mTLS certificates from intermediate PKI

# Issue mTLS certificates from intermediate PKI
path "pki_int/issue/internal-service" {
  capabilities = ["create", "update"]
}

# Read intermediate CA
path "pki_int/cert/ca" {
  capabilities = ["read"]
}

# Read root CA
path "pki/cert/ca" {
  capabilities = ["read"]
}

# Renew token
path "auth/token/renew-self" {
  capabilities = ["update"]
}
