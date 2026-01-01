# Vault Agent Configuration - Edge TLS Certificates
# Fetches certificates from pki/issue/edge-gateway

exit_after_auth = false
pid_file = "/tmp/vault-agent.pid"

# Auto-auth using Edge AppRole
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

# Edge TLS Server Certificate
template {
  source      = "/vault/config/templates/edge-server-cert.tpl"
  destination = "/vault/certs/edge-server.crt"
  command     = "echo 'Edge server certificate updated'"
}

# Edge TLS Server Private Key
template {
  source      = "/vault/config/templates/edge-server-key.tpl"
  destination = "/vault/certs/edge-server.key"
  perms       = "0600"
  command     = "echo 'Edge server key updated'"
}

# Edge CA Certificate
template {
  source      = "/vault/config/templates/edge-ca.tpl"
  destination = "/vault/certs/edge-ca.crt"
  command     = "echo 'Edge CA certificate updated'"
}

# Vault configuration
vault {
  address = "${VAULT_ADDR}"
  tls_skip_verify = true
}
