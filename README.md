# VytalMind Zero-Trust Gateway

A production-ready zero-trust gateway architecture using Envoy Proxy with dual-layer security:
- **Edge Gateway**: TLS termination, JWT validation, claim extraction
- **Internal Gateway**: mTLS authentication for internal service communication

## Architecture

```
Internet → Edge Envoy (TLS/JWT) → Internal Envoy (mTLS) → Backend Services
                ↓                           ↓
          Direct Backends         Secure Backends
```

## Features

### Edge Envoy
- ✅ TLS termination with Vault-managed certificates
- ✅ JWT/OAuth validation via Keycloak
- ✅ JWT claim extraction to custom headers (sub, email, roles, groups)
- ✅ Mixed routing (internal envoy + direct backends)
- ✅ Traffic splitting and canary deployments
- ✅ Full observability (Prometheus + OpenTelemetry)

### Internal Envoy
- ✅ mTLS authentication for internal services
- ✅ Vault PKI for certificate management (https://vault.odell.com:8200)
- ✅ Automatic certificate rotation
- ✅ SPIFFE-based identity

## Prerequisites

- **Docker** 20.10+ with Compose V2
- **Vault CLI** installed (`brew install vault`)
- **jq** installed (`brew install jq`)
- **Access to Vault** at https://vault.odell.com:8200
- **Vault admin token** for one-time PKI setup
- **Prometheus** at https://prometheus.odell.com (for metrics)
- 4GB available RAM

## Quick Start

### 1. Vault PKI Setup (One-Time)

First, configure the PKI engines in your Vault:

```bash
# Set your Vault admin token
export VAULT_TOKEN=<your-vault-admin-token>

# Run the Vault setup script
make vault-setup
```

This script will:
- Enable PKI engines (root for edge TLS, intermediate for mTLS)
- Create certificate roles
- Configure AppRole authentication
- Print AppRole credentials that you need to save

**Save the output!** You'll need the AppRole IDs for your `.env` file.

### 2. Configure Environment

```bash
# Copy the example environment file
cp .env.example .env

# Edit .env and add the AppRole credentials from step 1
nano .env
```

Update these values in `.env`:
```env
EDGE_VAULT_ROLE_ID=<from vault-setup output>
EDGE_VAULT_SECRET_ID=<from vault-setup output>
INTERNAL_VAULT_ROLE_ID=<from vault-setup output>
INTERNAL_VAULT_SECRET_ID=<from vault-setup output>
```

### 3. Start the Gateway

```bash
# Run the setup script
make setup

# Verify all services are healthy
make health
```

### 4. Configure Prometheus (Optional)

Add Envoy metrics scraping to your Prometheus at prometheus.odell.com:

```bash
# See detailed configuration guide
cat infrastructure/prometheus/README.md
```

Add the scrape jobs for edge-envoy (port 9901) and internal-envoy (port 9902) to your Prometheus configuration.

### 5. Test JWT Authentication

```bash
# Get a JWT token from Keycloak
TOKEN=$(make dev-token)

# Make an authenticated request
curl -k -H "Authorization: Bearer $TOKEN" https://localhost:443/api/simple/
```

## Service Endpoints

| Service | URL | Purpose |
|---------|-----|---------|
| Edge Gateway | https://localhost:443 | Main HTTPS entry point (external) |
| Edge Admin | http://localhost:9901 | Edge Envoy admin/metrics |
| Internal Gateway | http://internal-envoy:10000 | Internal mTLS proxy (from containers) |
| Internal Admin | http://localhost:9902 | Internal Envoy admin/metrics |
| Keycloak | http://localhost:8080 | OAuth/JWT provider |
| Prometheus | https://prometheus.odell.com | External metrics (see infrastructure/prometheus/README.md) |

## Configuration

### Keycloak Setup

Default realm: `vytalmind`

Default users:
- **Test User**: Username: `testuser`, Password: `password123`
- **Admin**: Username: `admin`, Password: `admin123`

### Testing JWT Authentication

```bash
# Get access token
TOKEN=$(curl -s -X POST http://localhost:8080/realms/vytalmind/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=edge-gateway" \
  -d "client_secret=your-client-secret-change-in-production" \
  -d "username=testuser" \
  -d "password=password123" \
  -d "grant_type=password" | jq -r '.access_token')

# Make authenticated request
curl -k -H "Authorization: Bearer $TOKEN" https://localhost:443/api/simple/

# Check JWT claims are extracted (view backend logs or access logs)
tail -f edge/logs/access.log | jq
```

### Routes

The edge Envoy is configured with these routes:

- `/public/health` - Public health check (no JWT required)
- `/api/simple/*` - Direct to backend-simple (JWT required)
- `/api/secure/*` - Through internal Envoy to backend-secure (JWT + mTLS)
- `/api/canary/*` - Traffic split 90/10 between backends

### JWT Claim Extraction

The Lua filter extracts these claims as HTTP headers:
- `X-JWT-Sub` - Subject (user ID)
- `X-JWT-Email` - Email address
- `X-JWT-Name` - Full name
- `X-JWT-Username` - Preferred username
- `X-JWT-Roles` - Comma-separated realm roles
- `X-JWT-Groups` - Comma-separated groups
- `X-JWT-Client-Roles` - Comma-separated client-specific roles
- `X-JWT-Tenant` - Tenant ID (if present)

## Certificate Management

### Automatic Rotation

Certificates are automatically rotated:
- **Edge TLS**: Renewed every 23 hours (1 year TTL)
- **Internal mTLS**: Renewed every 24 days (30 day TTL)

The Envoy bootstrap scripts handle this automatically.

### Manual Certificate Check

```bash
# View edge certificate
openssl x509 -in edge/certs/server.crt -noout -text

# View internal certificate
openssl x509 -in internal/certs/server.crt -noout -text

# Check expiration
make health
```

## Observability

### Prometheus Metrics

Metrics are exported to your existing Prometheus at **https://prometheus.odell.com**.

You need to configure Prometheus to scrape the Envoy metrics endpoints. See [infrastructure/prometheus/README.md](infrastructure/prometheus/README.md) for scrape configuration.

Metrics endpoints:
- Edge Envoy: http://localhost:9901/stats/prometheus
- Internal Envoy: http://localhost:9902/stats/prometheus

Key metrics:
- `envoy_http_downstream_rq_total` - Total requests
- `envoy_cluster_upstream_rq_time` - Upstream latency
- `envoy_http_downstream_rq_xx` - Response codes

### Access Logs

```bash
# Edge logs (JSON format)
tail -f edge/logs/access.log | jq

# Internal logs
tail -f internal/logs/access.log | jq

# Filter for specific user
tail -f edge/logs/access.log | jq 'select(.jwt_subject == "test-user-id")'
```

### Admin Interfaces

```bash
# Edge Envoy stats
curl http://localhost:9901/stats

# View configuration
curl http://localhost:9901/config_dump | jq

# Check clusters
curl http://localhost:9901/clusters

# Internal Envoy
curl http://localhost:9902/stats
```

## Troubleshooting

### Services not starting

```bash
# Check logs
docker compose logs edge-envoy
docker compose logs internal-envoy

# Verify Vault is reachable
curl -k https://vault.odell.com:8200/v1/sys/health

# Check certificates exist
ls -la edge/certs/ internal/certs/
```

### JWT validation failing

```bash
# Verify Keycloak is accessible from edge-envoy
docker exec edge-envoy curl http://keycloak:8080/realms/vytalmind/protocol/openid-connect/certs

# Check JWKS in Envoy config
curl http://localhost:9901/config_dump | jq '.configs[] | select(.["@type"] | contains("JwtAuthentication"))'

# Test token is valid
echo $TOKEN | cut -d. -f2 | base64 -d | jq
```

### Certificate errors

```bash
# Check Vault connectivity from containers
docker exec edge-envoy curl -k https://vault.odell.com:8200/v1/sys/health

# Verify AppRole credentials in .env
cat .env | grep VAULT

# Re-fetch certificates manually
docker compose restart edge-envoy internal-envoy
```

### Vault AppRole issues

```bash
# Test AppRole login
curl -k --request POST \
  --data '{"role_id":"YOUR_ROLE_ID","secret_id":"YOUR_SECRET_ID"}' \
  https://vault.odell.com:8200/v1/auth/approle/login

# Verify policy permissions
export VAULT_ADDR=https://vault.odell.com:8200
vault policy read edge-envoy
vault policy read internal-envoy
```

## Development

### Adding New Routes

Edit [edge/envoy.yaml](edge/envoy.yaml) route_config section:

```yaml
- match:
    prefix: /api/newservice/
  route:
    cluster: new_service_cluster
```

### Adding Backend Services

1. Add service to [docker-compose.yml](docker-compose.yml):

```yaml
new-service:
  image: your-service:latest
  networks:
    - internal-network  # Use internal for mTLS
```

2. Add cluster to [internal/envoy.yaml](internal/envoy.yaml)

### Modifying JWT Claims

Edit [edge/config/lua/jwt-claims-extractor.lua](edge/config/lua/jwt-claims-extractor.lua) to extract additional claims.

## Production Considerations

1. **Security**:
   - Change all default passwords in `.env`
   - Update Keycloak client secret
   - Enable Redis authentication
   - Use proper DNS names instead of localhost
   - Implement network policies
   - Enable Vault audit logging

2. **High Availability**:
   - Deploy multiple Envoy replicas behind load balancer
   - Use Redis Cluster for distributed state
   - Ensure Vault is running in HA mode
   - Add health checks and auto-recovery

3. **Monitoring**:
   - Set up Grafana dashboards
   - Configure alerting rules (cert expiration, error rates)
   - Implement log aggregation (ELK/Loki)
   - Add distributed tracing visualization

4. **Performance**:
   - Tune Envoy connection pools
   - Configure proper circuit breakers
   - Enable HTTP/2 and connection pooling
   - Load test and optimize worker threads

## Common Commands

```bash
# Start everything
make start

# Stop everything
make stop

# View logs
make logs
make logs-edge
make logs-internal

# Health check
make health

# Get JWT token
make dev-token

# Test authenticated request
make dev-request

# Clean up
make clean
```

## Architecture Details

### External Infrastructure

This gateway integrates with your existing infrastructure:

- **Vault** (https://vault.odell.com:8200)
  - PKI engine for TLS certificate issuance
  - Intermediate PKI for mTLS certificates
  - AppRole authentication for Envoy containers
  - Automatic certificate rotation

- **Prometheus** (https://prometheus.odell.com)
  - Metrics collection from Envoy admin endpoints
  - Scrapes edge-envoy:9901 and internal-envoy:9902
  - See `infrastructure/prometheus/README.md` for configuration

### Zero-Trust Boundaries

1. **Edge Network** (172.20.0.0/24)
   - Public-facing services
   - Redis, Keycloak, Edge Envoy
   - Direct backend services

2. **Internal Network** (172.21.0.0/24)
   - Isolated from external access
   - Internal Envoy only
   - mTLS-protected services
   - No direct internet access

3. **Edge Envoy** bridges both networks
   - Only entry point to internal network
   - Enforces JWT authentication
   - Extracts claims for authorization

### Certificate Hierarchy

```
Vault PKI (vault.odell.com:8200)
├── Root PKI (pki/)
│   └── Edge Gateway TLS Certificates
│       └── TTL: 8760h (1 year)
│
└── Intermediate PKI (pki_int/)
    └── Internal Service mTLS Certificates
        └── TTL: 720h (30 days)
        └── SPIFFE URIs: spiffe://vytalmind.local/service/*
```

### Authentication Flow

1. Client → Edge Envoy (HTTPS/TLS)
2. Edge validates JWT with Keycloak JWKS
3. Lua filter extracts claims to headers
4. Request routed to backend (direct or via internal)
5. Internal Envoy validates mTLS (if applicable)
6. Backend receives request with claim headers

## Support

For issues and questions, please open a GitHub issue or contact the infrastructure team.

## License

MIT
