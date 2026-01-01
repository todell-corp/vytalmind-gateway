# Vault Agent Configuration
# Manages certificates for both Edge and Internal Envoy

# Exit on error (don't retry indefinitely on misconfig)
exit_after_auth = false

# PID file for management
pid_file = "/tmp/vault-agent.pid"

# Auto-auth configuration using Edge AppRole (has access to both PKIs)
auto_auth {
  method {
    type = "approle"
    namespace = ""

    config = {
      role_id_file_path = "/vault/config/edge-role-id"
      secret_id_file_path = "/vault/config/edge-secret-id"
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

# Template for Edge TLS Certificate
template {
  source      = "/vault/config/edge-cert.tpl"
  destination = "/vault/certs/edge/server.crt"
  command     = "echo 'Edge certificate updated'"
}

template {
  source      = "/vault/config/edge-key.tpl"
  destination = "/vault/certs/edge/server.key"
  perms       = "0600"
  command     = "echo 'Edge key updated'"
}

template {
  source      = "/vault/config/edge-ca.tpl"
  destination = "/vault/certs/edge/ca.crt"
  command     = "echo 'Edge CA updated'"
}

# Template for Internal mTLS Server Certificate
template {
  source      = "/vault/config/internal-server-cert.tpl"
  destination = "/vault/certs/internal/server.crt"
  command     = "echo 'Internal server certificate updated'"
}

template {
  source      = "/vault/config/internal-server-key.tpl"
  destination = "/vault/certs/internal/server.key"
  perms       = "0600"
  command     = "echo 'Internal server key updated'"
}

# Template for Internal mTLS Client Certificate
template {
  source      = "/vault/config/internal-client-cert.tpl"
  destination = "/vault/certs/internal/client.crt"
  command     = "echo 'Internal client certificate updated'"
}

template {
  source      = "/vault/config/internal-client-key.tpl"
  destination = "/vault/certs/internal/client.key"
  perms       = "0600"
  command     = "echo 'Internal client key updated'"
}

template {
  source      = "/vault/config/internal-ca.tpl"
  destination = "/vault/certs/internal/ca.crt"
  command     = "echo 'Internal CA updated'"
}

# Vault configuration
vault {
  address = "${VAULT_ADDR}"

  # Skip TLS verification for self-signed certs (adjust for production)
  tls_skip_verify = true
}
