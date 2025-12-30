# VytalMind Gateway Deployment Guide

## Overview

This zero-trust gateway is designed to integrate with your existing infrastructure at odell.com:
- **Vault**: https://vault.odell.com:8200 (PKI & secrets)
- **Prometheus**: https://prometheus.odell.com (metrics)

## Deployment Checklist

### Phase 1: Vault Configuration (One-Time Setup)

- [ ] Install Vault CLI: `brew install vault`
- [ ] Install jq: `brew install jq`
- [ ] Get Vault admin token
- [ ] Run PKI setup:
  ```bash
  export VAULT_TOKEN=<your-admin-token>
  make vault-setup
  ```
- [ ] Save AppRole credentials from output

### Phase 2: Environment Configuration

- [ ] Copy environment template:
  ```bash
  cp .env.example .env
  ```
- [ ] Update `.env` with AppRole credentials:
  - `EDGE_VAULT_ROLE_ID`
  - `EDGE_VAULT_SECRET_ID`
  - `INTERNAL_VAULT_ROLE_ID`
  - `INTERNAL_VAULT_SECRET_ID`
- [ ] Update Keycloak client secret (if needed)

### Phase 3: Deploy Services

- [ ] Run setup:
  ```bash
  make setup
  ```
- [ ] Verify health:
  ```bash
  make health
  ```
- [ ] Check all services are running:
  ```bash
  docker compose ps
  ```

### Phase 4: Configure Prometheus (Optional)

- [ ] Review scrape configuration: `cat infrastructure/prometheus/README.md`
- [ ] Add scrape jobs to prometheus.odell.com configuration:
  - Edge Envoy: `<host>:9901/stats/prometheus`
  - Internal Envoy: `<host>:9902/stats/prometheus`
- [ ] Ensure Prometheus can reach the admin ports
- [ ] Test metrics endpoints:
  ```bash
  curl http://localhost:9901/stats/prometheus
  curl http://localhost:9902/stats/prometheus
  ```

### Phase 5: Testing

- [ ] Get JWT token:
  ```bash
  make dev-token
  ```
- [ ] Test authenticated request:
  ```bash
  make dev-request
  ```
- [ ] Verify JWT claims in logs:
  ```bash
  tail -f edge/logs/access.log | jq '.jwt_subject'
  ```
- [ ] Test traffic splitting (canary):
  ```bash
  TOKEN=$(make dev-token)
  curl -k -H "Authorization: Bearer $TOKEN" https://localhost:443/api/canary/
  ```

## Service URLs

| Service | URL | Purpose |
|---------|-----|---------|
| Edge Gateway | https://localhost:443 | Main HTTPS entry |
| Edge Admin | http://localhost:9901 | Metrics & config |
| Internal Admin | http://localhost:9902 | Metrics & config |
| Keycloak | http://localhost:8080 | OAuth/JWT |
| Vault | https://vault.odell.com:8200 | PKI & secrets |
| Prometheus | https://prometheus.odell.com | Metrics |

## Network Architecture

```
                    External Traffic
                           ↓
                   Edge Envoy (443)
                    /          \
        TLS Termination    JWT Validation
                   /              \
          Direct Backend    Internal Envoy (mTLS)
         (edge-network)           ↓
                            Secure Backends
                           (internal-network)
```

## Security Notes

### AppRole Authentication
- Edge and Internal Envoy use separate AppRoles
- Tokens auto-renew (1h TTL, 24h max)
- Secrets never expire (secret_id_ttl=0)
- Each AppRole has minimal required permissions

### Certificate Management
- **Edge TLS**: 1 year TTL, auto-renews every 23 hours
- **Internal mTLS**: 30 day TTL, auto-renews every 24 days
- Certificates fetched from Vault at container startup
- Background daemon handles renewal
- SPIFFE URIs for service identity

### Network Isolation
- Internal network has `internal: true` (no external access)
- Only Edge Envoy bridges edge and internal networks
- Zero-trust: all communication requires valid JWT or mTLS

## Troubleshooting

### Services won't start
```bash
# Check logs
docker compose logs edge-envoy
docker compose logs internal-envoy

# Verify Vault connectivity
curl -k https://vault.odell.com:8200/v1/sys/health
```

### Certificate errors
```bash
# Check if certs were fetched
ls -la edge/certs/ internal/certs/

# Test AppRole authentication
curl -k --request POST \
  --data "{\"role_id\":\"$EDGE_VAULT_ROLE_ID\",\"secret_id\":\"$EDGE_VAULT_SECRET_ID\"}" \
  https://vault.odell.com:8200/v1/auth/approle/login

# Restart to re-fetch certs
docker compose restart edge-envoy internal-envoy
```

### JWT validation failing
```bash
# Verify Keycloak JWKS is accessible
docker exec edge-envoy curl http://keycloak:8080/realms/vytalmind/protocol/openid-connect/certs

# Check JWT config
curl http://localhost:9901/config_dump | jq '.configs[] | select(.["@type"] | contains("JwtAuthentication"))'
```

### Prometheus not scraping
```bash
# Test metrics endpoints
curl http://localhost:9901/stats/prometheus | head
curl http://localhost:9902/stats/prometheus | head

# Check if Prometheus can reach endpoints
# (from prometheus.odell.com server)
curl http://<envoy-host>:9901/stats/prometheus
```

## Production Hardening

Before production deployment:

1. **Change all default credentials**
   - Update Keycloak admin password
   - Update Keycloak client secret
   - Enable Redis authentication

2. **Use proper DNS names**
   - Configure real domain names
   - Update allowed_domains in Vault PKI roles

3. **Network security**
   - Configure firewall rules
   - Use host networking or ingress controller
   - Implement rate limiting at infrastructure level

4. **Monitoring**
   - Set up Grafana dashboards
   - Configure alerting for cert expiration
   - Monitor error rates and latency

5. **High availability**
   - Deploy multiple Envoy replicas
   - Use load balancer
   - Ensure Vault HA is configured

## Maintenance

### Certificate rotation (manual)
```bash
# Certificates auto-rotate, but for manual rotation:
docker compose restart edge-envoy internal-envoy
```

### View certificate expiration
```bash
make health
# Or manually:
openssl x509 -in edge/certs/server.crt -noout -dates
```

### Update Envoy configuration
```bash
# Edit edge/envoy.yaml or internal/envoy.yaml
# Then restart:
docker compose restart edge-envoy  # or internal-envoy
```

### View real-time logs
```bash
make logs-edge
make logs-internal
# Or:
tail -f edge/logs/access.log | jq
```

## Support

- **Configuration Issues**: Check this guide and README.md
- **Vault Issues**: Verify Vault is accessible and AppRole credentials are correct
- **Prometheus Issues**: See infrastructure/prometheus/README.md
- **General Issues**: Run `make health` for diagnostics
