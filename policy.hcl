# Allow issuing certificates for this gateway
path "pki-intermediate/issue/vytalmind-api-gateway" {
  capabilities = ["create", "update"]
}

# Allow issuing certificates for keycloak
path "pki-intermediate/issue/keycloak" {
  capabilities = ["create", "update"]
}

# Allow reading the INTERMEDIATE CA (this was missing)
path "pki-intermediate/cert/ca" {
  capabilities = ["read"]
}

# (Optional but safe) Allow listing intermediate certs
path "pki-intermediate/certs/*" {
  capabilities = ["read", "list"]
}

# Allow reading the ROOT CA (trust anchor)
path "pki-root/cert/ca" {
  capabilities = ["read"]
}
