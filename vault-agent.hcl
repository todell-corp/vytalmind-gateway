exit_after_auth = false
pid_file = "/tmp/vault-agent.pid"

# Auto-auth using AppRole
auto_auth {
  method {
    type = "approle"
    namespace = ""

    config = {
      role_id_file_path = "/tmp/role-id"
      secret_id_file_path = "/tmp/secret-id"
      remove_secret_id_file_after_reading = false
    }
  }

  sink {
    type = "file"
    config = {
      path = "/tmp/vault-token"
    }
  }
}

# TLS Server Certificate
template {
  contents    = <<EOF
{{ with secret "pki-edge/issue/edge-gateway" (printf "common_name=%s" (env "TLS_DOMAIN")) "alt_names=localhost" (printf "ttl=%s" (env "TLS_CERT_TTL")) }}{{ .Data.certificate }}{{ end }}
EOF
  destination = "/vault/certs/tls-server.crt"
  command     = "echo 'TLS server certificate updated'"
}

# TLS Server Private Key
template {
  contents    = <<EOF
{{ with secret "pki-edge/issue/edge-gateway" (printf "common_name=%s" (env "TLS_DOMAIN")) "alt_names=localhost" (printf "ttl=%s" (env "TLS_CERT_TTL")) }}{{ .Data.private_key }}{{ end }}
EOF
  destination = "/vault/certs/tls-server.key"
  perms       = "0600"
  command     = "echo 'TLS server key updated'"
}

# CA Certificate
template {
  contents    = <<EOF
{{ with secret "pki-edge/issue/edge-gateway" (printf "common_name=%s" (env "TLS_DOMAIN")) "alt_names=localhost" (printf "ttl=%s" (env "TLS_CERT_TTL")) }}{{ range .Data.ca_chain }}{{ . }}{{ end }}{{ end }}
EOF
  destination = "/vault/certs/tls-ca.crt"
  command     = "echo 'CA certificate updated'"
}

# Vault configuration
vault {
  address = "https://vault.odell.com:8200"
  tls_skip_verify = true
}
