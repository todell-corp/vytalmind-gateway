# Vault Agent Configuration - Internal mTLS + Apicurio Certificates
# Fetches certificates from pki_int/issue/internal-service

exit_after_auth = false
pid_file = "/tmp/vault-agent.pid"

# Auto-auth using Internal AppRole
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

# ========================================
# Internal mTLS Certificates
# ========================================

# Internal Server Certificate
template {
  source      = "/vault/config/templates/internal-server-cert.tpl"
  destination = "/vault/certs/internal-server.crt"
  command     = "echo 'Internal server certificate updated'"
}

# Internal Server Private Key
template {
  source      = "/vault/config/templates/internal-server-key.tpl"
  destination = "/vault/certs/internal-server.key"
  perms       = "0600"
  command     = "echo 'Internal server key updated'"
}

# Internal Client Certificate
template {
  source      = "/vault/config/templates/internal-client-cert.tpl"
  destination = "/vault/certs/internal-client.crt"
  command     = "echo 'Internal client certificate updated'"
}

# Internal Client Private Key
template {
  source      = "/vault/config/templates/internal-client-key.tpl"
  destination = "/vault/certs/internal-client.key"
  perms       = "0600"
  command     = "echo 'Internal client key updated'"
}

# Internal CA Certificate
template {
  source      = "/vault/config/templates/internal-ca.tpl"
  destination = "/vault/certs/internal-ca.crt"
  command     = "echo 'Internal CA certificate updated'"
}

# ========================================
# Apicurio Registry Certificates
# ========================================

# Apicurio Server Certificate
template {
  source      = "/vault/config/templates/apicurio-server-cert.tpl"
  destination = "/vault/certs/apicurio-server.crt"
  command     = "echo 'Apicurio server certificate updated'"
}

# Apicurio Server Private Key
template {
  source      = "/vault/config/templates/apicurio-server-key.tpl"
  destination = "/vault/certs/apicurio-server.key"
  perms       = "0600"
  command     = "echo 'Apicurio server key updated'"
}

# Apicurio CA Certificate
template {
  source      = "/vault/config/templates/apicurio-ca.tpl"
  destination = "/vault/certs/apicurio-ca.crt"
  command     = "echo 'Apicurio CA certificate updated'"
}

# ========================================
# Keycloak Certificates
# ========================================

# Keycloak Server Certificate
template {
  source      = "/vault/config/templates/keycloak-server-cert.tpl"
  destination = "/vault/certs/keycloak-server.crt"
  command     = "echo 'Keycloak server certificate updated'"
}

# Keycloak Server Private Key
template {
  source      = "/vault/config/templates/keycloak-server-key.tpl"
  destination = "/vault/certs/keycloak-server.key"
  perms       = "0600"
  command     = "echo 'Keycloak server key updated'"
}

# Keycloak CA Certificate
template {
  source      = "/vault/config/templates/keycloak-ca.tpl"
  destination = "/vault/certs/keycloak-ca.crt"
  command     = "echo 'Keycloak CA certificate updated'"
}

# Vault configuration
vault {
  address = "${VAULT_ADDR}"
  tls_skip_verify = true
}
