# Allow issuing certificates for this gateway
path "pki-intermediate/issue/vytalmind-api-gateway" {
  capabilities = ["create", "update"]
}

# Allow issuing certificates for keycloak
path "pki-intermediate/issue/keycloak" {
  capabilities = ["create", "update"]
}

# Allow issuing certificates for vytalmind-chronos
path "pki-intermediate/issue/vytalmind-chronos" {
  capabilities = ["create", "update"]
}

# Allow issuing certificates for vytalmind-admin
path "pki-intermediate/issue/vytalmind-admin" {
  capabilities = ["create", "update"]
}

# Allow issuing certificates for vytalmind-api
path "pki-intermediate/issue/vytalmind-api" {
  capabilities = ["create", "update"]
}

# Allow issuing certificates for nexus
path "pki-intermediate/issue/nexus" {
  capabilities = ["create", "update"]
}

# Allow issuing certificates for vytalmind-search
path "pki-intermediate/issue/vytalmind-search" {
  capabilities = ["create", "update"]
}

# Allow issuing certificates for vytalmind-identity
path "pki-intermediate/issue/vytalmind-identity" {
  capabilities = ["create", "update"]
}

# Allow issuing certificates for langfuse
path "pki-intermediate/issue/langfuse" {
  capabilities = ["create", "update"]
}

# Allow issuing certificates for vytalmind-graphql
path "pki-intermediate/issue/vytalmind-graphql" {
  capabilities = ["create", "update"]
}

# Allow issuing certificates for ventusmind-codec
path "pki-intermediate/issue/ventusmind-codec" {
  capabilities = ["create", "update"]
}

# Allow issuing certificates for internal-vytalmind-search
path "pki-intermediate/issue/internal-vytalmind-search" {
  capabilities = ["create", "update"]
}

# Allow issuing certificates for internal-vytalmind-api
path "pki-intermediate/issue/internal-vytalmind-api" {
  capabilities = ["create", "update"]
}

# Allow issuing certificates for pgadmin
path "pki-intermediate/issue/pgadmin" {
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
