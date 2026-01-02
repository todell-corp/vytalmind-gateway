# Internal Envoy OAuth2 Configuration

This directory contains OAuth2 filter configuration files for Apicurio authentication.

## Secret Files

### token_secret.yaml
Contains the Keycloak client secret for the `apicurio-registry` client.

**Setup:**
1. Login to Keycloak admin console
2. Navigate to: Clients → apicurio-registry → Credentials
3. Copy the Client Secret value
4. Replace `REPLACE_WITH_KEYCLOAK_CLIENT_SECRET` in `token_secret.yaml` with the actual secret

### hmac_secret.yaml
Contains a random 32-byte secret used for HMAC signing of OAuth cookies.

**Setup:**
```bash
# Generate a random 32-byte secret
openssl rand -base64 32

# Replace REPLACE_WITH_RANDOM_32_BYTE_HMAC_SECRET in hmac_secret.yaml with the generated value
```

## Keycloak Client Configuration

For OAuth2 to work, configure the Keycloak client `apicurio-registry`:

1. **Valid Redirect URIs:** `https://apicurio.odell.com/oauth2/callback`
2. **Web Origins:** `https://apicurio.odell.com`
3. **Access Type:** confidential
4. **Standard Flow Enabled:** ON
5. **Direct Access Grants Enabled:** ON

## How It Works

1. User accesses `https://apicurio.odell.com`
2. OAuth2 filter detects no authentication cookie
3. User is redirected to `https://keycloak.odell.com/realms/ventusmind/protocol/openid-connect/auth`
4. User authenticates with Keycloak
5. Keycloak redirects back to `https://apicurio.odell.com/oauth2/callback` with auth code
6. OAuth2 filter exchanges code for tokens with Keycloak backend
7. OAuth2 filter stores token in encrypted cookie
8. JWT filter validates the token from cookie
9. Request is forwarded to Apicurio backend
