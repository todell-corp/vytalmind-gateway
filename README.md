# VytalMind Gateway

A minimal Envoy Proxy gateway providing TLS termination with Vault-managed certificates.

## Architecture

```
Internet → Envoy (TLS termination) → /health endpoint
           ↓
    Vault Agent (auto-renew certs)
```

## Features

- ✅ TLS termination with Vault-managed certificates
- ✅ Automatic certificate renewal via Vault Agent
- ✅ Health check endpoint
- ✅ Admin interface for metrics and debugging
- ✅ Minimal configuration, easy to extend

## Prerequisites

- **Docker** 20.10+ with Compose V2
- **Access to Vault** at https://vault.odell.com:8200
- **Vault AppRole credentials** (VAULT_ROLE_ID and VAULT_SECRET_ID)

## Quick Start

### 1. Configure Environment

```bash
# Copy the example environment file
cp .env.example .env

# Edit .env and add your Vault credentials
nano .env
```

Update these required values in `.env`:
```env
VAULT_ROLE_ID=<your-vault-approle-role-id>
VAULT_SECRET_ID=<your-vault-approle-secret-id>
TLS_DOMAIN=vytalmind.odell.com
TLS_CERT_TTL=168h
```

### 2. Start the Gateway

```bash
# Start services
make start

# View logs
make logs

# Check health
make health
```

### 3. Test the Gateway

```bash
# Test health endpoint
curl -k https://localhost:443/health

# Check admin interface
curl http://localhost:9901/stats
```

## Available Commands

```bash
make start   # Start gateway services
make stop    # Stop all services
make logs    # View envoy logs
make health  # Check health endpoint
make clean   # Stop and remove volumes
```

## Service Endpoints

| Service | URL | Purpose |
|---------|-----|---------|
| Gateway (HTTPS) | https://localhost:443 | TLS entry point |
| Health Endpoint | https://localhost:443/health | Health check |
| Admin Interface | http://localhost:9901 | Metrics and debugging |

## Monitoring

### Admin Interface

The Envoy admin interface provides:
- Config dump: `curl http://localhost:9901/config_dump | jq`
- Stats: `curl http://localhost:9901/stats`
- Prometheus metrics: `curl http://localhost:9901/stats/prometheus`
- Health check: `curl http://localhost:9901/ready`

### Certificate Status

```bash
# View certificate details
docker exec envoy openssl x509 -in /etc/envoy/certs/tls-server.crt -noout -text

# Check expiration
docker exec envoy openssl x509 -in /etc/envoy/certs/tls-server.crt -noout -dates
```

## Troubleshooting

### Services won't start

```bash
# Check container status
docker compose ps

# View logs
docker compose logs

# Check Vault Agent logs
docker compose logs vault-agent
```

### Certificate issues

```bash
# Verify certificates exist
docker exec vault-agent ls -la /vault/certs/

# Force certificate renewal
docker compose restart vault-agent
```

### Connection issues

```bash
# Test admin interface
curl http://localhost:9901/ready

# Test HTTPS endpoint
curl -k https://localhost:443/health

# View Envoy config
curl http://localhost:9901/config_dump | jq
```

## Extending the Gateway

This minimal setup can be extended with:

### Add Backend Routes

Edit [envoy.yaml](envoy.yaml) to add upstream clusters and routes. See [CLAUDE.md](CLAUDE.md#adding-backend-routes) for examples.

### Add JWT Authentication

Add JWT validation filter to authenticate requests with Keycloak or other OAuth providers. See [CLAUDE.md](CLAUDE.md#adding-jwt-authentication).

### Add Rate Limiting

Add Redis and rate limiting filter for request throttling. See [CLAUDE.md](CLAUDE.md#adding-rate-limiting).

### Add Observability

Add OpenTelemetry tracing for distributed request tracking. See [CLAUDE.md](CLAUDE.md#adding-observability).

## Configuration Files

- **[envoy.yaml](envoy.yaml)**: Envoy proxy configuration
- **[vault/vault-agent.hcl](vault/vault-agent.hcl)**: Vault Agent certificate management
- **[vault/policy.hcl](vault/policy.hcl)**: Vault policy template
- **[docker-compose.yml](docker-compose.yml)**: Service orchestration
- **[Dockerfile](Dockerfile)**: Envoy container image
- **[Makefile](Makefile)**: Common commands

## Documentation

- **[CLAUDE.md](CLAUDE.md)**: Detailed technical documentation for Claude Code
- **[README.md](README.md)**: This file - user documentation

## CI/CD Integration

This project includes GitHub Actions workflows for:

- **[deploy.yml](.github/workflows/deploy.yml)**: Automated deployment
- **[health-check.yml](.github/workflows/health-check.yml)**: Periodic health monitoring

Required GitHub secrets:
- `VAULT_ROLE_ID`: Vault AppRole Role ID
- `VAULT_SECRET_ID`: Vault AppRole Secret ID
- `TLS_DOMAIN` (optional): Certificate domain
- `TLS_CERT_TTL` (optional): Certificate TTL

## Architecture Philosophy

This gateway follows these principles:

1. **Minimalism**: Only essential features (TLS termination)
2. **Automation**: Vault Agent handles certificates automatically
3. **Extensibility**: Easy to add features incrementally
4. **Observability**: Admin interface provides full visibility
5. **Simplicity**: Two services, clear purpose

## License

Proprietary - VytalMind
