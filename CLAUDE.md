# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

VytalMind Zero-Trust Gateway is a production-ready dual-layer Envoy Proxy architecture implementing zero-trust security principles. The architecture is designed to support a **future GraphQL Gateway** that will sit between the two Envoy layers.

**Ultimate Architecture:**
```
Client → Edge Envoy → GraphQL Gateway → Internal Envoy → Backend Services
```

Currently deployed without GraphQL layer:
```
Internet → Edge Envoy (TLS/JWT) → Internal Envoy (mTLS) → Backend Services
              ↓                           ↓
        Direct Backends           Secure Backends
```

## Critical Architecture Concepts

### Network Topology

**Two-Subnet Design:**
- **Edge Network** (172.20.0.0/24): Internet-facing tier
  - Edge Envoy, Redis, direct backends, (future: GraphQL Gateway)
  - Handles external traffic, TLS termination, JWT validation

- **Internal Network** (172.21.0.0/24): Service mesh tier
  - Internal Envoy, secure backends, (future: GraphQL Gateway)
  - **IMPORTANT**: Does NOT have `internal: true` in docker-compose.yml
  - This network needs to route to services on other hosts/networks
  - Zero-trust is enforced via Envoy policies (mTLS, auth), not Docker network isolation

**Why two subnets matter:**
- Clear tier separation for monitoring and firewall rules
- Future GraphQL Gateway will bridge both networks (like Edge Envoy currently does)
- Network segmentation provides observability benefits

### Service Communication

**Edge Envoy** (bridges both networks):
- Connected to BOTH edge-network and internal-network
- Routes to external services not in docker-compose context
- Envoy upstream clusters can point to remote hosts
- Needs access to host network for routing to external upstreams

**Internal Envoy** (internal-network only):
- Routes to backends both local (in docker-compose) and remote (on other hosts)
- Upstream cluster configurations define services outside this deployment
- mTLS enforcement happens at Envoy policy level, not network isolation

### JWT Authentication & Audiences

**JWT Audience Configuration** is critical for security and service integration.

The `audience` (aud) claim in JWT tokens specifies which services are authorized to accept the token. This prevents token reuse across different services and ensures tokens are only used for their intended purpose.

**Current Configuration** in [edge/envoy.yaml](edge/envoy.yaml):
```yaml
providers:
  keycloak:
    issuer: http://keycloak:8080/realms/vytalmind
    audiences:
      - edge-gateway  # Only tokens with this audience are accepted
```

**How it works:**
1. Client requests token from Keycloak with specific audience (client ID)
2. Keycloak issues JWT with `"aud": "edge-gateway"` claim
3. Edge Envoy validates the token and checks audience matches configuration
4. If audience doesn't match, request is rejected with 401 Unauthorized

**Keycloak Client Configuration:**
- Client ID should match the audience value (typically `edge-gateway`)
- Add "Audience" protocol mapper if needed:
  - Mapper Type: Audience
  - Included Client Audience: `edge-gateway`
  - Add to access token: ON

**Multiple Audiences:**
You can configure multiple valid audiences if needed:
```yaml
audiences:
  - edge-gateway
  - api-gateway
  - legacy-service
```

**Debugging audience issues:**
```bash
# Decode JWT to inspect audience claim
echo $TOKEN | cut -d. -f2 | base64 -d | jq '.aud'

# Should output: "edge-gateway" or ["edge-gateway", ...]
```

**IMPORTANT**: When integrating new services or changing Keycloak clients, always verify the audience configuration matches between:
1. Keycloak client settings (Client ID or Audience mapper)
2. Envoy JWT authentication configuration (audiences list)
3. Client token requests (audience parameter in OAuth flow)

### Certificate Hierarchy

**Vault PKI** at vault.odell.com:8200 (external, always required):
```
pki-root/ (Root PKI)
├─ Root CA: CN=odell.com Root CA
├─ Valid: 2025-12-31 to 2035-12-29 (10 years)
└─ Signs intermediate CAs

pki-edge/ (Edge Intermediate PKI)
├─ Intermediate CA: CN=Odell Edge Intermediate CA
├─ Valid: 2025-12-31 to 2026-12-31 (1 year)
├─ Role: edge-gateway
│   ├─ Allowed domains: odell.com (with subdomains)
│   ├─ Max TTL: 604800s (7 days / 168 hours)
│   └─ IP SANs: Not allowed
├─ Issued to: Edge Envoy TLS certificates
└─ Managed by: edge-vault-agent (AppRole: edge-envoy, Policy: vault-agent)

pki-intermediate/ (Internal Intermediate PKI)
├─ Intermediate CA: CN=odell.com Intermediate CA
├─ Valid: 2025-12-31 to 2030-12-30 (5 years)
├─ Role: internal-services
│   ├─ Allowed domains: odell.com (with subdomains)
│   ├─ Max TTL: 2592000s (30 days / 720 hours)
│   ├─ SPIFFE URIs: spiffe://odell.com/*
│   └─ Server + Client flags: enabled
├─ Issued to: Internal Envoy mTLS, Apicurio, backend services
└─ Managed by: internal-vault-agent (AppRole: internal-envoy, Policy: pki-internal-services)
           and: envoy-apicurio (AppRole: envoy-apicurio, Policy: pki-internal-services)
```

**Vault Agent Sidecar Architecture:**
- **Edge Vault Agent**: Dedicated sidecar container managing Edge TLS certificates only
  - Uses Edge AppRole credentials: `edge-envoy` → policy `vault-agent`
  - Access to: `pki-edge/issue/edge-gateway` and `pki-intermediate/issue/internal-services`
  - Writes to `edge-certs` Docker volume
  - Auto-renews certificates before expiration (checks every 5 minutes)
- **Internal Vault Agent**: Dedicated sidecar container managing Internal mTLS + Apicurio certificates
  - Uses Internal AppRole credentials: `internal-envoy` → policy `pki-internal-services`
  - Access to: `pki-intermediate/issue/internal-services` only
  - Writes to `internal-certs` Docker volume
  - Manages 8 certificate files (5 internal mTLS + 3 Apicurio)
  - Auto-renews certificates before expiration

**Certificate Rotation:**
- Edge TLS: Auto-renewed by edge-vault-agent (Vault Agent default: check every 5 minutes)
- Internal mTLS: Auto-renewed by internal-vault-agent
- No manual intervention required - Vault Agent handles renewals automatically
- Each Envoy reads certificates from its dedicated volume (read-only mount)

### Deployment Modes

**Production Mode** (default):
- Deploys: Edge Envoy, Internal Envoy, Redis
- Uses external: Vault, Prometheus, Keycloak, OpenTelemetry
- Command: `docker compose up -d` or `make setup`

**Standalone Mode** (development):
- Deploys: Core gateway + Keycloak + OTel + Jaeger
- Still requires external: Vault, Prometheus
- Command: `docker compose -f docker-compose.yml -f docker-compose.shared.yml up -d` or `make setup-standalone`

## Development Commands

### Initial Setup (One-Time)

```bash
# 1. Setup Vault PKI (requires VAULT_TOKEN)
export VAULT_TOKEN=<your-vault-admin-token>
make vault-setup

# 2. Configure environment
cp .env.example .env
# Edit .env with AppRole credentials from vault-setup output

# 3. Start gateway (choose mode)
make setup              # Production mode
make setup-standalone   # Standalone mode (with local Keycloak/OTel)
```

### Service Management

```bash
# Start/stop
make start              # Production mode
make start-standalone   # Standalone mode
make stop               # Stop all services
make restart            # Restart services

# Health and logs
make health             # Check all service health
make logs               # All logs (follow mode)
make logs-edge          # Edge Envoy only
make logs-internal      # Internal Envoy only

# Vault Agent sidecar logs
docker logs -f edge-vault-agent          # Edge certificate management
docker logs -f internal-vault-agent      # Internal certificate management

# View access logs (JSON formatted)
tail -f edge/logs/access.log | jq
tail -f internal/logs/access.log | jq
```

### Testing

```bash
# Get JWT token from Keycloak
make dev-token

# Make authenticated request
make dev-request

# Full test
make test

# Manual test
TOKEN=$(make -s dev-token)
curl -k -H "Authorization: Bearer $TOKEN" https://localhost:443/api/simple/
```

### Vault Operations

```bash
# Verify Vault connectivity
curl -k https://vault.odell.com:8200/v1/sys/health

# Test AppRole login
curl -k --request POST \
  --data '{"role_id":"YOUR_ROLE_ID","secret_id":"YOUR_SECRET_ID"}' \
  https://vault.odell.com:8200/v1/auth/approle/login

# View policies
export VAULT_ADDR=https://vault.odell.com:8200
vault policy read edge-envoy
vault policy read internal-envoy
```

### Certificate Operations

```bash
# View certificates from Vault Agent volumes
docker exec edge-vault-agent ls -la /vault/certs/
docker exec internal-vault-agent ls -la /vault/certs/

# View certificates from Envoy containers
docker exec edge-envoy ls -la /etc/envoy/certs/
docker exec internal-envoy ls -la /etc/envoy/certs/

# Inspect certificate details
docker exec edge-envoy openssl x509 -in /etc/envoy/certs/edge-server.crt -noout -text
docker exec internal-envoy openssl x509 -in /etc/envoy/certs/internal-server.crt -noout -text

# Force certificate renewal (restart Vault Agent sidecars)
docker compose restart edge-vault-agent internal-vault-agent

# Verify certificate files exist
docker exec edge-envoy sh -c "ls -la /etc/envoy/certs/ | grep edge-"
docker exec internal-envoy sh -c "ls -la /etc/envoy/certs/ | grep internal-"
docker exec internal-envoy sh -c "ls -la /etc/envoy/certs/ | grep apicurio-"
```

### Envoy Admin Interface

```bash
# Edge Envoy (port 9901)
curl http://localhost:9901/stats
curl http://localhost:9901/config_dump | jq
curl http://localhost:9901/clusters
curl http://localhost:9901/stats/prometheus

# Internal Envoy (port 9902)
curl http://localhost:9902/stats
curl http://localhost:9902/config_dump | jq
curl http://localhost:9902/clusters
curl http://localhost:9902/stats/prometheus
```

### Cleanup

```bash
make clean    # Stop services and clean up volumes/certs
```

## Configuration Files

### Key Envoy Configurations

**[edge/envoy.yaml](edge/envoy.yaml)**:
- TLS termination settings
- JWT authentication (Keycloak JWKS)
- JWT claim extraction (Lua filter)
- Route configuration (public, direct, internal routing)
- Rate limiting configuration
- OpenTelemetry tracing
- Cluster definitions (backends, keycloak, redis, internal-envoy)

**[internal/envoy.yaml](internal/envoy.yaml)**:
- mTLS listener configuration
- Client certificate validation (currently `require_client_certificate: false`)
- Route configuration for internal services
- Cluster definitions for backend services
- OpenTelemetry tracing

**[edge/config/lua/jwt-claims-extractor.lua](edge/config/lua/jwt-claims-extractor.lua)**:
- Extracts JWT claims to HTTP headers
- Headers: X-JWT-Sub, X-JWT-Email, X-JWT-Name, X-JWT-Username, X-JWT-Roles, X-JWT-Groups, X-JWT-Client-Roles, X-JWT-Tenant

### Bootstrap Scripts

**[edge/config/bootstrap/vault-tls-init.sh](edge/config/bootstrap/vault-tls-init.sh)**:
- Authenticates to Vault via AppRole
- Fetches TLS certificates from PKI
- Runs on Edge Envoy container startup

**[internal/config/bootstrap/vault-mtls-init.sh](internal/config/bootstrap/vault-mtls-init.sh)**:
- Authenticates to Vault via AppRole
- Fetches mTLS certificates from PKI intermediate
- Runs on Internal Envoy container startup

**[internal/config/cert-renewal.sh](internal/config/cert-renewal.sh)**:
- Automatic certificate renewal script
- Runs periodically to refresh certificates before expiration

## External Dependencies

### Always Required

**Vault** (vault.odell.com:8200):
- PKI certificate authority
- AppRole authentication
- Required for both deployment modes

**Prometheus** (prometheus.odell.com):
- Metrics collection from Envoy admin endpoints
- Configuration: See [infrastructure/prometheus/README.md](infrastructure/prometheus/README.md)

### Production Mode Uses External

**Keycloak** (keycloak.odell.com):
- OAuth 2.0 / OpenID Connect provider
- JWT token issuance and validation
- Override with KEYCLOAK_URL in .env

**OpenTelemetry Collector** (otel.odell.com:4317):
- Distributed tracing aggregation
- Override with OTEL_EXPORTER_OTLP_ENDPOINT in .env

## Common Tasks

### Adding New Routes

Edit [edge/envoy.yaml](edge/envoy.yaml) route_config section:

```yaml
- match:
    prefix: /api/newservice/
  route:
    cluster: new_service_cluster
```

Then add the cluster definition in the clusters section.

### Adding Backend Services

1. Add service to [docker-compose.yml](docker-compose.yml):

```yaml
new-service:
  image: your-service:latest
  networks:
    - internal-network  # For mTLS routing via internal-envoy
    # OR
    - edge-network      # For direct routing from edge-envoy
```

2. Add cluster to appropriate envoy.yaml:
   - Edge-direct: [edge/envoy.yaml](edge/envoy.yaml)
   - Internal (mTLS): [internal/envoy.yaml](internal/envoy.yaml)

### Adding Remote/External Upstreams

Services not in docker-compose can be routed to via Envoy cluster configurations:

```yaml
clusters:
  - name: remote_service
    connect_timeout: 1s
    type: STRICT_DNS  # or LOGICAL_DNS
    dns_lookup_family: V4_ONLY
    load_assignment:
      cluster_name: remote_service
      endpoints:
        - lb_endpoints:
            - endpoint:
                address:
                  socket_address:
                    address: remote-host.example.com
                    port_value: 8080
```

**IMPORTANT**: The internal-network does NOT have `internal: true` in docker-compose.yml, which allows routing to external hosts.

### Configuring JWT Audiences

JWT audiences control which services can accept tokens. This is critical for multi-service architectures.

**To change or add audiences:**

1. Edit [edge/envoy.yaml](edge/envoy.yaml) JWT authentication section:

```yaml
providers:
  keycloak:
    issuer: http://keycloak:8080/realms/vytalmind
    audiences:
      - edge-gateway      # Existing
      - new-service-name  # Add new audience
```

2. Configure corresponding Keycloak client:
   - Login to Keycloak admin console
   - Navigate to: Realm → Clients → Select/Create client
   - Set Client ID to match audience (e.g., `new-service-name`)
   - OR add Audience mapper:
     - Client Scopes → Create new scope
     - Add Mapper → Audience
     - Included Client Audience: `new-service-name`
     - Add to access token: ON

3. Test the configuration:

```bash
# Get token for specific audience (adjust Keycloak client credentials)
TOKEN=$(curl -s -X POST "http://localhost:8080/realms/vytalmind/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=new-service-name" \
  -d "client_secret=YOUR_CLIENT_SECRET" \
  -d "grant_type=client_credentials" | jq -r '.access_token')

# Verify audience in token
echo $TOKEN | cut -d. -f2 | base64 -d | jq '.aud'

# Test request
curl -k -H "Authorization: Bearer $TOKEN" https://localhost:443/api/simple/
```

4. Restart Edge Envoy to apply changes:

```bash
docker compose restart edge-envoy
```

**Common scenarios:**

- **Single service**: Use one audience (current setup)
- **Multiple gateways**: Add audience per gateway instance
- **Service migration**: Temporarily allow both old and new audiences
- **Development vs Production**: Use different audiences per environment

### Modifying JWT Claim Extraction

Edit [edge/config/lua/jwt-claims-extractor.lua](edge/config/lua/jwt-claims-extractor.lua) to extract additional claims from the JWT payload.

After modification, restart Edge Envoy:
```bash
docker compose restart edge-envoy
```

### Changing Certificate TTLs

Edit [.env](.env):
```env
TLS_CERT_TTL=8760h  # Edge TLS
PKI_TTL=720h        # Internal mTLS
```

Re-run Vault setup and restart services:
```bash
make vault-setup
make restart
```

## Service Endpoints

| Service | URL | Purpose |
|---------|-----|---------|
| Edge Gateway | https://localhost:443 | Main HTTPS entry point |
| Edge Admin | http://localhost:9901 | Envoy admin/metrics |
| Edge Vault Agent | (internal) | Certificate management for Edge TLS |
| Internal Gateway | http://internal-envoy:10000 | Internal mTLS proxy (from containers) |
| Internal Admin | http://localhost:9902 | Envoy admin/metrics |
| Internal Vault Agent | (internal) | Certificate management for Internal mTLS + Apicurio |
| Keycloak (standalone) | http://localhost:8080 | OAuth/JWT provider |
| Vault (external) | https://vault.odell.com:8200 | PKI and secrets |
| Prometheus (external) | https://prometheus.odell.com | Metrics collection |

## Troubleshooting

### Services Not Starting

```bash
# Check container logs
docker compose logs edge-envoy
docker compose logs internal-envoy
docker compose logs edge-vault-agent
docker compose logs internal-vault-agent

# Verify Vault Agent health
docker ps | grep vault-agent
docker compose ps edge-vault-agent internal-vault-agent

# Verify Vault connectivity from Vault Agent containers
docker exec edge-vault-agent curl -k https://vault.odell.com:8200/v1/sys/health
docker exec internal-vault-agent curl -k https://vault.odell.com:8200/v1/sys/health

# Check certificates were fetched
docker exec edge-vault-agent ls -la /vault/certs/
docker exec internal-vault-agent ls -la /vault/certs/
docker exec edge-envoy ls -la /etc/envoy/certs/
docker exec internal-envoy ls -la /etc/envoy/certs/
```

### JWT Validation Failing

```bash
# Test Keycloak access from edge-envoy
docker exec edge-envoy curl http://keycloak:8080/realms/vytalmind/protocol/openid-connect/certs

# View JWT config in Envoy
curl http://localhost:9901/config_dump | jq '.configs[] | select(.["@type"] | contains("JwtAuthentication"))'

# Decode token to verify claims
echo $TOKEN | cut -d. -f2 | base64 -d | jq

# Check audience mismatch (common issue)
echo $TOKEN | cut -d. -f2 | base64 -d | jq '.aud'
# Should output: "edge-gateway" (or one of configured audiences)

# View configured audiences in Envoy
curl http://localhost:9901/config_dump | jq '.configs[].dynamic_listeners[].active_state.listener.filter_chains[].filters[].typed_config.http_filters[] | select(.name == "envoy.filters.http.jwt_authn") | .typed_config.providers[].audiences'

# If audience doesn't match, either:
# 1. Update Keycloak client/mapper to include correct audience
# 2. Update edge/envoy.yaml audiences list to accept token's audience
```

### Certificate Issues

```bash
# Test Vault AppRole credentials
cat .env | grep VAULT

# Check Vault Agent logs for errors
docker logs edge-vault-agent
docker logs internal-vault-agent

# Verify Vault Agent can authenticate
docker exec edge-vault-agent cat /tmp/vault-token
docker exec internal-vault-agent cat /tmp/vault-token

# Manually trigger certificate refresh (restart Vault Agent sidecars)
docker compose restart edge-vault-agent internal-vault-agent

# Check certificate expiration
docker exec edge-envoy openssl x509 -in /etc/envoy/certs/edge-server.crt -noout -dates
docker exec internal-envoy openssl x509 -in /etc/envoy/certs/internal-server.crt -noout -dates

# Verify certificate files exist in volumes
docker exec edge-vault-agent ls -la /vault/certs/
docker exec internal-vault-agent ls -la /vault/certs/
```

### Routing Issues

```bash
# Check cluster health
curl http://localhost:9901/clusters

# View route configuration
curl http://localhost:9901/config_dump | jq '.configs[] | select(.["@type"] | contains("RouteConfiguration"))'

# Check upstream connectivity
docker exec edge-envoy curl http://backend-simple:5678
docker exec internal-envoy curl http://backend-secure:5678
```

## Architecture Notes for Future Work

### GraphQL Gateway Integration

When adding GraphQL Gateway:

1. **Network Configuration**:
   - GraphQL service must be on BOTH edge-network and internal-network
   - Similar to edge-envoy bridging both networks

2. **Routing Changes**:
   - Edge Envoy routes to GraphQL Gateway (not directly to backends)
   - GraphQL Gateway routes to Internal Envoy
   - Internal Envoy routes to backends

3. **Expected Traffic Flow**:
   ```
   Client → Edge Envoy → GraphQL Gateway → Internal Envoy → Backends
   ```

4. **Docker Compose Entry**:
   ```yaml
   graphql-gateway:
     image: graphql-service:latest
     networks:
       - edge-network     # Receives from edge-envoy
       - internal-network # Sends to internal-envoy
   ```

### mTLS Enforcement

Currently `require_client_certificate: false` in [internal/envoy.yaml](internal/envoy.yaml) line 98.

To enable full mTLS:
1. Set `require_client_certificate: true`
2. Ensure backend services have Vault-issued certificates
3. Configure backend services to present client certificates
4. Update backend service configurations to use mTLS transport sockets

## Environment Variables

Key variables in [.env](.env):

```bash
# Vault AppRole (from vault-setup output)
EDGE_VAULT_ROLE_ID=...
EDGE_VAULT_SECRET_ID=...
INTERNAL_VAULT_ROLE_ID=...
INTERNAL_VAULT_SECRET_ID=...

# External service URLs (production mode)
KEYCLOAK_URL=https://keycloak.odell.com
OTEL_EXPORTER_OTLP_ENDPOINT=https://otel.odell.com:4317

# Certificate configuration
TLS_DOMAIN=gateway.vytalmind.local
TLS_CERT_TTL=8760h
PKI_TTL=720h
```
