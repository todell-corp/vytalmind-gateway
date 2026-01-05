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
