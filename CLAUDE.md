# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

VytalMind Gateway is a minimal Envoy Proxy deployment providing TLS termination with Vault-managed certificates. This is a barebones foundation that can be extended with additional features as needed.

**Current Architecture:**
```
Internet → Envoy (TLS termination) → /health endpoint
           ↓
    Vault Agent (auto-renew certs)
```

## Core Components

### Envoy Proxy
- **Purpose**: TLS termination and basic HTTP routing
- **Configuration**: [envoy.yaml](envoy.yaml) in project root
- **Ports**:
  - 443 (HTTPS listener)
  - 9901 (Admin interface)
- **Features**:
  - TLS termination using Vault-issued certificates
  - Basic `/health` endpoint (returns "OK")
  - Stdout access logging
  - Admin interface for metrics and debugging

### Vault Agent
- **Purpose**: Automatic certificate management
- **Configuration**: [vault-agent.hcl](vault-agent.hcl) in project root
- **Vault PKI**: Uses `pki-edge/issue/edge-gateway` role
- **Certificates Managed**:
  - `tls-server.crt` - Server certificate
  - `tls-server.key` - Private key
  - `tls-ca.crt` - CA certificate
- **Auto-Renewal**: Certificates automatically renewed before expiration

### Certificate Management

**Vault PKI Hierarchy:**
```
pki-root/ (Root CA at vault.odell.com:8200)
  └─ pki-intermediate/ (Intermediate CA)
      └─ keycloak role
          ├─ Allowed domains: keycloak.odell.com
          ├─ Alt names: keycloak, localhost
          ├─ Default TTL: 168h (7 days)
          └─ Auto-renewed by Vault Agent
```

**AppRole Authentication:**
- Role: `edge-envoy` (reused from previous architecture)
- Policy: `vault-agent`
- Credentials: Set in `.env` as `VAULT_ROLE_ID` and `VAULT_SECRET_ID`

### Installing Root CA in Ubuntu Trust Store

For Ubuntu and browsers to trust the Vault-issued certificates, install the root CA:

1. **Extract the root CA from vault-agent**:
   ```bash
   docker exec vault-agent cat /vault/certs/root-ca.crt > /tmp/vault-root-ca.pem
   ```

2. **Install in Ubuntu**:
   ```bash
   sudo cp /tmp/vault-root-ca.pem /usr/local/share/ca-certificates/vault-root-ca.crt
   sudo update-ca-certificates
   ```

3. **Verify**:
   ```bash
   curl https://keycloak.odell.com/health  # Should work without -k
   openssl s_client -connect keycloak.odell.com:443 -servername keycloak.odell.com < /dev/null 2>&1 | grep "Verify return code"
   # Should show: Verify return code: 0 (ok)
   ```

4. **For Firefox** (uses own trust store):
   - Settings → Privacy & Security → Certificates → View Certificates
   - Authorities tab → Import
   - Select `/tmp/vault-root-ca.pem`
   - Check "Trust this CA to identify websites"

### Certificate Files

After the vault-agent updates, the following certificate files are available:

- `tls-server.crt` - Default domain server certificate
- `tls-server.key` - Default domain private key
- `tls-ca.crt` - CA chain (legacy, may be empty)
- `keycloak-fullchain.crt` - **Full chain: server + intermediate CA** (use this for TLS)
- `keycloak-server.key` - Keycloak private key
- `root-ca.crt` - Root CA certificate (for system trust installation)

### Certificate Rendering Script

All certificate rendering is handled by [scripts/render-vault-cert.sh](scripts/render-vault-cert.sh):

**Usage:**
```bash
render-vault-cert.sh <service-name> <json-path> [reload-cmd]
```

**Parameters:**
- `service-name`: Service identifier (e.g., "keycloak", "api-gateway")
- `json-path`: Path to Vault-generated JSON file with cert data
- `reload-cmd`: (Optional) Command to run after rendering (e.g., signal service to reload)

**Output Files:**
- `${service-name}.leaf.pem` - Server certificate only
- `${service-name}.issuing_ca.pem` - Issuing CA certificate
- `${service-name}.fullchain.pem` - Full chain (leaf + CA) - **use this for TLS**
- `${service-name}.key` - Private key (600 permissions)

**Example - Adding a new service:**
```hcl
template {
  contents = <<EOF
{{- with secret "pki-intermediate/issue/my-service"
   "common_name=my-service.odell.com"
   "ttl=168h" -}}
{
  "certificate": {{ .Data.certificate | toJSON }},
  "issuing_ca":  {{ .Data.issuing_ca  | toJSON }},
  "private_key": {{ .Data.private_key | toJSON }}
}
{{- end -}}
EOF
  destination = "/vault/certs/my-service.json"
  perms       = "0600"
  command     = "/vault/scripts/render-vault-cert.sh my-service /vault/certs/my-service.json"
}
```

## File Structure

```
vytalmind-gateway/
├── envoy.yaml           # Envoy configuration
├── vault-agent.hcl      # Vault Agent certificate management
├── Dockerfile           # Envoy container image
├── docker-compose.yml   # Service orchestration
├── .env                 # Environment variables (not in git)
├── .env.example         # Environment template
├── Makefile             # Common commands
├── CLAUDE.md            # This file
├── README.md            # User documentation
├── scripts/
│   └── render-vault-cert.sh   # Certificate rendering script
└── .github/
    └── workflows/
        ├── deploy.yml         # Deployment automation
        └── health-check.yml   # Health monitoring
```

## Development Commands

### Setup

```bash
# 1. Copy environment template
cp .env.example .env

# 2. Edit .env with your Vault credentials
# VAULT_ROLE_ID=<from-vault-admin>
# VAULT_SECRET_ID=<from-vault-admin>
# TLS_DOMAIN=gateway.odell.com
# TLS_CERT_TTL=168h

# 3. Start services
make start
```

### Daily Operations

```bash
# Start gateway
make start

# Stop gateway
make stop

# View logs
make logs

# Check health
make health

# Clean up (stops services and removes volumes)
make clean
```

### Debugging

```bash
# Check if services are running
docker compose ps

# View Vault Agent logs (certificate renewal)
docker compose logs vault-agent

# View Envoy logs
docker compose logs envoy

# Check certificates were fetched
docker exec vault-agent ls -la /vault/certs/

# View certificate details
docker exec envoy openssl x509 -in /etc/envoy/certs/tls-server.crt -noout -text

# Test health endpoint
curl -k https://localhost:443/health

# Check Envoy admin interface
curl http://localhost:9901/stats
curl http://localhost:9901/config_dump | jq
```

## Configuration Files

### [envoy.yaml](envoy.yaml)

Minimal Envoy configuration:
- **HTTPS Listener** (port 443):
  - TLS termination with Vault certificates
  - Single route: `/health` returns 200 OK
  - Access logging to stdout
- **Admin Interface** (port 9901):
  - Metrics, stats, config dump
  - Health check endpoint

### [vault-agent.hcl](vault-agent.hcl)

Vault Agent configuration:
- AppRole authentication
- Three certificate templates (inline)
- Auto-renewal before expiration
- Environment variable support for `TLS_DOMAIN` and `TLS_CERT_TTL`

### [docker-compose.yml](docker-compose.yml)

Two services:
1. **vault-agent**: Fetches and renews certificates
2. **envoy**: TLS termination gateway

Single volume:
- `certs`: Shared between vault-agent (write) and envoy (read-only)

### [.env](.env)

Required environment variables:
```bash
VAULT_ADDR=https://vault.odell.com:8200
VAULT_ROLE_ID=<your-role-id>
VAULT_SECRET_ID=<your-secret-id>
TLS_DOMAIN=gateway.odell.com
TLS_CERT_TTL=168h
```

## Extending the Gateway

This minimal setup can be extended with:

### Adding Backend Routes

Edit [envoy.yaml](envoy.yaml) to add upstream clusters and routes:

```yaml
routes:
  - match:
      prefix: "/api/"
    route:
      cluster: backend_service

clusters:
  - name: backend_service
    connect_timeout: 1s
    type: STRICT_DNS
    load_assignment:
      cluster_name: backend_service
      endpoints:
        - lb_endpoints:
            - endpoint:
                address:
                  socket_address:
                    address: backend.example.com
                    port_value: 8080
```

### Adding JWT Authentication

To add JWT validation (requires Keycloak or OAuth provider):
1. Add JWT filter to HTTP connection manager
2. Configure JWKS endpoint
3. Specify audience requirements
4. Add authentication rules per route

### Adding Rate Limiting

To add rate limiting (requires Redis):
1. Add Redis service to [docker-compose.yml](docker-compose.yml)
2. Configure rate limit filter in [envoy.yaml](envoy.yaml)
3. Define rate limit descriptors and actions

### Adding Observability

To add tracing (requires OpenTelemetry Collector):
1. Add OTel collector service to [docker-compose.yml](docker-compose.yml)
2. Configure tracing in [envoy.yaml](envoy.yaml)
3. Add trace decorators to routes

## Troubleshooting

### Services Not Starting

```bash
# Check container status
docker compose ps

# View all logs
docker compose logs

# Check Vault Agent specifically
docker compose logs vault-agent

# Verify Vault connectivity
docker exec vault-agent curl -k https://vault.odell.com:8200/v1/sys/health
```

### Certificate Issues

```bash
# Verify certificates exist
docker exec vault-agent ls -la /vault/certs/
docker exec envoy ls -la /etc/envoy/certs/

# Check certificate expiration
docker exec envoy openssl x509 -in /etc/envoy/certs/tls-server.crt -noout -dates

# Force certificate renewal (restart Vault Agent)
docker compose restart vault-agent

# Wait for renewal and check logs
docker compose logs -f vault-agent
```

### Connection Issues

```bash
# Test admin interface (should work)
curl http://localhost:9901/ready

# Test HTTPS endpoint (might fail if cert domain doesn't match)
curl -k https://localhost:443/health

# Check if Envoy is listening
netstat -tlnp | grep envoy

# View Envoy config
curl http://localhost:9901/config_dump | jq
```

### Vault Authentication Failures

```bash
# Verify environment variables are set
docker compose config | grep VAULT

# Check Vault Agent can authenticate
docker exec vault-agent cat /tmp/vault-token

# If empty, check logs for auth errors
docker compose logs vault-agent | grep -i error

# Verify AppRole credentials in .env match Vault
```

## Service Endpoints

| Service | URL | Purpose |
|---------|-----|---------|
| Gateway (HTTPS) | https://localhost:443 | TLS entry point |
| Health Endpoint | https://localhost:443/health | Health check |
| Admin Interface | http://localhost:9901 | Metrics and debugging |
| Vault (external) | https://vault.odell.com:8200 | PKI and certificates |

## Common Tasks

### Changing Certificate TTL

Edit [.env](.env):
```bash
TLS_CERT_TTL=720h  # Change from 168h (7 days) to 720h (30 days)
```

Restart services:
```bash
make stop
make start
```

### Changing TLS Domain

Edit [.env](.env):
```bash
TLS_DOMAIN=new-gateway.example.com
```

Restart services:
```bash
make stop
make start
```

### Viewing Metrics

```bash
# Prometheus format metrics
curl http://localhost:9901/stats/prometheus

# JSON stats
curl http://localhost:9901/stats?format=json | jq

# Specific stat
curl http://localhost:9901/stats | grep http.ingress_http
```

## CI/CD Integration

### GitHub Actions Workflows

**[.github/workflows/deploy.yml](.github/workflows/deploy.yml)**:
- Validates secrets (VAULT_ROLE_ID, VAULT_SECRET_ID)
- Builds and deploys services
- Runs health checks
- Tests HTTPS endpoint

**[.github/workflows/health-check.yml](.github/workflows/health-check.yml)**:
- Runs every 6 hours
- Checks Envoy health
- Monitors certificate expiration
- Generates health reports
- Alerts on failures

### Required GitHub Secrets

```bash
VAULT_ROLE_ID        # Vault AppRole Role ID
VAULT_SECRET_ID      # Vault AppRole Secret ID
TLS_DOMAIN           # (optional) Defaults to gateway.odell.com
TLS_CERT_TTL         # (optional) Defaults to 168h
```

## Architecture Philosophy

This gateway follows these principles:

1. **Minimalism**: Only essential features (TLS termination)
2. **Flat Structure**: No subdirectories, everything at root
3. **Automation**: Vault Agent handles certificates automatically
4. **Extensibility**: Easy to add features incrementally
5. **Observability**: Admin interface provides full visibility
6. **Simplicity**: Single network, two services, clear purpose

## Migration Notes

This is a simplified version of a previous dual-layer architecture (edge + internal Envoy). The consolidation removed:
- JWT authentication and claims extraction
- mTLS support
- Rate limiting
- OpenTelemetry tracing
- Multiple networks
- Backend example services
- Standalone mode (local Keycloak/OTel)

These features can be re-added as needed by extending the base configuration.
