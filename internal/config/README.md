# Internal Envoy OAuth2 Configuration

This directory contains OAuth2 filter configuration files for Apicurio authentication.

## Secret Files

### token_secret.yaml
Contains the Keycloak client secret for the `apicurio-registry` client.

### hmac_secret.yaml
Contains a random 32-byte secret used for HMAC signing of OAuth cookies.

## Setup Options

### Option 1: Manual Configuration (Development)

1. **Get Keycloak Client Secret:**
   - Login to Keycloak admin console
   - Navigate to: Clients → apicurio-registry → Credentials
   - Copy the Client Secret value

2. **Generate HMAC Secret:**
   ```bash
   openssl rand -base64 32
   ```

3. **Update Files:**
   - Replace `REPLACE_WITH_KEYCLOAK_CLIENT_SECRET` in `token_secret.yaml`
   - Replace `REPLACE_WITH_RANDOM_32_BYTE_HMAC_SECRET` in `hmac_secret.yaml`

### Option 2: GitHub Secrets (CI/CD - Recommended)

Store secrets in GitHub repository settings and use GitHub Actions to generate secret files from templates during deployment.

**GitHub Secrets to create:**
- `OAUTH2_CLIENT_SECRET` - Keycloak client secret
- `OAUTH2_HMAC_SECRET` - Random 32-byte base64 secret

**In your GitHub Actions workflow:**
```yaml
- name: Generate OAuth2 Secret Files
  run: |
    # Generate token_secret.yaml from template
    sed "s/OAUTH2_CLIENT_SECRET_PLACEHOLDER/${{ secrets.OAUTH2_CLIENT_SECRET }}/g" \
      internal/config/token_secret.yaml.template > internal/config/token_secret.yaml

    # Generate hmac_secret.yaml from template
    sed "s/OAUTH2_HMAC_SECRET_PLACEHOLDER/${{ secrets.OAUTH2_HMAC_SECRET }}/g" \
      internal/config/hmac_secret.yaml.template > internal/config/hmac_secret.yaml
```

### Option 3: Environment Variables + .env File (Local Development)

1. **Create `.env` file:**
   ```bash
   OAUTH2_CLIENT_SECRET=your_keycloak_client_secret
   OAUTH2_HMAC_SECRET=your_generated_hmac_secret
   ```

2. **Generate secret files from templates:**
   ```bash
   # Generate token_secret.yaml
   sed "s/OAUTH2_CLIENT_SECRET_PLACEHOLDER/$OAUTH2_CLIENT_SECRET/g" \
     internal/config/token_secret.yaml.template > internal/config/token_secret.yaml

   # Generate hmac_secret.yaml
   sed "s/OAUTH2_HMAC_SECRET_PLACEHOLDER/$OAUTH2_HMAC_SECRET/g" \
     internal/config/hmac_secret.yaml.template > internal/config/hmac_secret.yaml

   # Start services
   docker compose up -d
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
