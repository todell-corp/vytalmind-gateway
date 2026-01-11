exit_after_auth = false
pid_file = "/tmp/vault-agent.pid"

auto_auth {
  method {
    type = "approle"
    namespace = ""
    config = {
      role_id_file_path   = "/tmp/role-id"
      secret_id_file_path = "/tmp/secret-id"
      remove_secret_id_file_after_reading = false
    }
  }

  sink {
    type = "file"
    config = { path = "/tmp/vault-token" }
  }
}

# 1) Issue ONCE and save the full response as JSON
template {
  contents = <<EOF
{{- with secret "pki-intermediate/issue/keycloak"
   "common_name=keycloak.odell.com"
   "alt_names=localhost"
   (printf "ttl=%s" (env "TLS_CERT_TTL")) -}}
{
  "certificate": {{ .Data.certificate | toJSON }},
  "issuing_ca":  {{ .Data.issuing_ca  | toJSON }},
  "private_key": {{ .Data.private_key | toJSON }}
}
{{- end -}}
EOF
  destination = "/vault/certs/keycloak.json"
  perms       = "0600"
  command     = "/vault/scripts/render-vault-cert.sh keycloak /vault/certs/keycloak.json"
}

# Chronos service certificate
template {
  contents = <<EOF
{{- with secret "pki-intermediate/issue/chronos"
   "common_name=chronos.odell.com"
   "alt_names=localhost"
   (printf "ttl=%s" (env "TLS_CERT_TTL")) -}}
{
  "certificate": {{ .Data.certificate | toJSON }},
  "issuing_ca":  {{ .Data.issuing_ca  | toJSON }},
  "private_key": {{ .Data.private_key | toJSON }}
}
{{- end -}}
EOF
  destination = "/vault/certs/chronos.json"
  perms       = "0600"
  command     = "/vault/scripts/render-vault-cert.sh chronos /vault/certs/chronos.json"
}

# VytalMind Admin service certificate
template {
  contents = <<EOF
{{- with secret "pki-intermediate/issue/vytalmind-admin"
   "common_name=vytalmind-admin.odell.com"
   "alt_names=localhost"
   (printf "ttl=%s" (env "TLS_CERT_TTL")) -}}
{
  "certificate": {{ .Data.certificate | toJSON }},
  "issuing_ca":  {{ .Data.issuing_ca  | toJSON }},
  "private_key": {{ .Data.private_key | toJSON }}
}
{{- end -}}
EOF
  destination = "/vault/certs/vytalmind-admin.json"
  perms       = "0600"
  command     = "/vault/scripts/render-vault-cert.sh vytalmind-admin /vault/certs/vytalmind-admin.json"
}

# VytalMind API service certificate
template {
  contents = <<EOF
{{- with secret "pki-intermediate/issue/vytalmind-api"
   "common_name=vytalmind-api.odell.com"
   "alt_names=localhost"
   (printf "ttl=%s" (env "TLS_CERT_TTL")) -}}
{
  "certificate": {{ .Data.certificate | toJSON }},
  "issuing_ca":  {{ .Data.issuing_ca  | toJSON }},
  "private_key": {{ .Data.private_key | toJSON }}
}
{{- end -}}
EOF
  destination = "/vault/certs/vytalmind-api.json"
  perms       = "0600"
  command     = "/vault/scripts/render-vault-cert.sh vytalmind-api /vault/certs/vytalmind-api.json"
}

# Nexus service certificate
template {
  contents = <<EOF
{{- with secret "pki-intermediate/issue/nexus"
   "common_name=nexus.odell.com"
   "alt_names=localhost"
   (printf "ttl=%s" (env "TLS_CERT_TTL")) -}}
{
  "certificate": {{ .Data.certificate | toJSON }},
  "issuing_ca":  {{ .Data.issuing_ca  | toJSON }},
  "private_key": {{ .Data.private_key | toJSON }}
}
{{- end -}}
EOF
  destination = "/vault/certs/nexus.json"
  perms       = "0600"
  command     = "/vault/scripts/render-vault-cert.sh nexus /vault/certs/nexus.json"
}

# VytalMind Search service certificate
template {
  contents = <<EOF
{{- with secret "pki-intermediate/issue/vytalmind-search"
   "common_name=vytalmind-search.odell.com"
   "alt_names=localhost"
   (printf "ttl=%s" (env "TLS_CERT_TTL")) -}}
{
  "certificate": {{ .Data.certificate | toJSON }},
  "issuing_ca":  {{ .Data.issuing_ca  | toJSON }},
  "private_key": {{ .Data.private_key | toJSON }}
}
{{- end -}}
EOF
  destination = "/vault/certs/vytalmind-search.json"
  perms       = "0600"
  command     = "/vault/scripts/render-vault-cert.sh vytalmind-search /vault/certs/vytalmind-search.json"
}

# VytalMind Identity service certificate
template {
  contents = <<EOF
{{- with secret "pki-intermediate/issue/vytalmind-identity"
   "common_name=vytalmind-identity.odell.com"
   "alt_names=localhost"
   (printf "ttl=%s" (env "TLS_CERT_TTL")) -}}
{
  "certificate": {{ .Data.certificate | toJSON }},
  "issuing_ca":  {{ .Data.issuing_ca  | toJSON }},
  "private_key": {{ .Data.private_key | toJSON }}
}
{{- end -}}
EOF
  destination = "/vault/certs/vytalmind-identity.json"
  perms       = "0600"
  command     = "/vault/scripts/render-vault-cert.sh vytalmind-identity /vault/certs/vytalmind-identity.json"
}

# 2) Root CA (trust anchor) — correct endpoint is /cert/ca
template {
  contents = <<EOF
{{ with secret "pki-root/cert/ca" }}{{ .Data.certificate }}{{ end }}
EOF
  destination = "/vault/cert/odell-root-ca.crt"
  command     = "echo Root CA updated"
}

vault {
  address = "https://vault.odell.com:8200"
  tls_skip_verify = true
}
