# Runbook: Adding a New TLS Terminated Service

This runbook describes the step-by-step process for adding a new service with TLS termination to the VytalMind Gateway.

## Overview

The VytalMind Gateway uses Envoy for TLS termination with certificates managed by HashiCorp Vault. Adding a new service requires configuring:
1. Vault PKI role and AppRole authentication
2. Vault Agent certificate template
3. Envoy SNI-based filter chain
4. Envoy backend cluster

## Prerequisites

- [ ] Vault admin access (VAULT_TOKEN set)
- [ ] Service backend is running and accessible
- [ ] DNS configured to point service domain to gateway
- [ ] Service details known:
  - Service name (e.g., `chronos`)
  - Fully qualified domain name (e.g., `chronos.odell.com`)
  - Backend port (e.g., `8080`)
  - Certificate TTL (default: `168h`)

## Step-by-Step Process

### Step 1: Set up Vault Resources

Run the setup script to create the PKI role, policy, and AppRole:

```bash
./scripts/setup-vault-service.sh <service-name> <fqdn> "localhost" <ttl>
```

**Example:**
```bash
./scripts/setup-vault-service.sh chronos chronos.odell.com "localhost" 168h
```

**What this creates:**
- PKI role: `pki-intermediate/roles/<service-name>`
- Vault policy: `vault-agent-<service-name>`
- AppRole: `<service-name>` (or updates existing AppRole with new policy)

**Validation:**
- Script should output: `✓ Certificate issuance verified`
- If errors occur, check that the domain follows the pattern `*.odell.com`

**Note:** The script is idempotent - safe to run multiple times.

### Step 2: Update Vault Policy

Edit [vault/policy.hcl](../vault/policy.hcl) to grant the AppRole permission to issue certificates for the new service.

**Location:** Add after the last service's PKI issue path, before the intermediate CA section.

**Template:**
```hcl
# Allow issuing certificates for <service-name>
path "pki-intermediate/issue/<service-name>" {
  capabilities = ["create", "update"]
}
```

**Example (chronos):**
```hcl
# Allow issuing certificates for chronos
path "pki-intermediate/issue/chronos" {
  capabilities = ["create", "update"]
}
```

**Write the updated policy to Vault:**
```bash
vault policy write vault-agent-vytalmind-api-gateway vault/policy.hcl
```

**Expected output:**
```
Success! Uploaded policy: vault-agent-vytalmind-api-gateway
```

**Note:** The vault-agent will use the new policy on its next token renewal (within 24h) or immediately after restart.

### Step 3: Add Vault Agent Template

Edit [vault/vault-agent.hcl](../vault/vault-agent.hcl) to add a certificate template for the new service.

**Location:** Add after the last service template, before the root CA template.

**Template:**
```hcl
# <Service-name> service certificate
template {
  contents = <<EOF
{{- with secret "pki-intermediate/issue/<service-name>"
   "common_name=<fqdn>"
   "alt_names=localhost"
   (printf "ttl=%s" (env "TLS_CERT_TTL")) -}}
{
  "certificate": {{ .Data.certificate | toJSON }},
  "issuing_ca":  {{ .Data.issuing_ca  | toJSON }},
  "private_key": {{ .Data.private_key | toJSON }}
}
{{- end -}}
EOF
  destination = "/vault/certs/<service-name>.json"
  perms       = "0600"
  command     = "/vault/scripts/render-vault-cert.sh <service-name> /vault/certs/<service-name>.json"
}
```

**Example (chronos):**
```hcl
# Chronos service certificate
template {
  contents = <<EOF
{{- with secret "pki-intermediate/issue/chronos"
   "common_name=chronos.odell.com"
   "alt_names=localhost"
   (printf "ttl=%s" (env "TLS_CERT_TTL")) -}}
{
  "certificate": {{ .Data.certificate | toJSON }},
  "issuing_ca":  {{ .Data.issuing_ca  | toJSON }},
  "private_key": {{ .Data.private_key | toJSON }}
}
{{- end -}}
EOF
  destination = "/vault/certs/chronos.json"
  perms       = "0600"
  command     = "/vault/scripts/render-vault-cert.sh chronos /vault/certs/chronos.json"
}
```

### Step 4: Add Envoy Filter Chain

Edit [envoy.yaml](../envoy.yaml) to add an SNI-based filter chain for the new service.

**Location:** In the `https_listener` → `filter_chains` section, add after the last service filter chain, before the default filter chain.

**Template:**
```yaml
      # <Service-name> filter chain with SNI matching
      - filter_chain_match:
          server_names: ["<fqdn>"]
        filters:
          - name: envoy.filters.network.http_connection_manager
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
              stat_prefix: ingress_http_<service-name>
              codec_type: AUTO
              access_log:
                - name: envoy.access_loggers.stdout
                  typed_config:
                    "@type": type.googleapis.com/envoy.extensions.access_loggers.stream.v3.StdoutAccessLog
              route_config:
                name: <service-name>_route
                virtual_hosts:
                  - name: <service-name>
                    domains: ["*"]
                    routes:
                      - match:
                          prefix: "/"
                        route:
                          cluster: <service-name>_backend
              http_filters:
                - name: envoy.filters.http.router
                  typed_config:
                    "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
        transport_socket:
          name: envoy.transport_sockets.tls
          typed_config:
            "@type": type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.DownstreamTlsContext
            common_tls_context:
              tls_certificate_sds_secret_configs:
                - name: <service-name>_cert
                  sds_config:
                    path_config_source:
                      path: /etc/envoy/certs/<service-name>-sds.yaml
                    resource_api_version: V3
```

**CRITICAL: SDS Secret Name Convention**
⚠️ The `name` field MUST match exactly what the render script generates in the SDS file.

The render script creates the secret name as: `<service-name>_cert` where:
- The service name part uses the SAME format as the filename (with hyphens)
- An underscore separates the service name from `_cert`

**Examples:**
- Service: `chronos` → Secret name: `chronos_cert`
- Service: `vytalmind-admin` → Secret name: `vytalmind-admin_cert` (NOT `vytalmind_admin_cert`)
- Service: `vytalmind-search` → Secret name: `vytalmind-search_cert` (NOT `vytalmind_search_cert`)

**Common mistake:** Using underscores throughout (e.g., `vytalmind_search_cert`) instead of preserving hyphens in the service name portion.

**How to verify:** After deployment, check the generated SDS file:
```bash
docker exec vault-agent cat /vault/certs/<service-name>-sds.yaml
```
The `name:` field in that file shows the exact string to use in envoy.yaml.

**Example (chronos):**
See lines 55-92 in [envoy.yaml](../envoy.yaml)

### Step 5: Add Envoy Backend Cluster

Edit [envoy.yaml](../envoy.yaml) to add a backend cluster definition.

**Location:** In the `clusters` section, add after the last cluster.

**Template:**
```yaml
  - name: <service-name>_backend
    connect_timeout: 5s
    type: STRICT_DNS
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: <service-name>_backend
      endpoints:
        - lb_endpoints:
            - endpoint:
                address:
                  socket_address:
                    address: <backend-address>
                    port_value: <backend-port>
```

**Example (chronos):**
```yaml
  - name: chronos_backend
    connect_timeout: 5s
    type: STRICT_DNS
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: chronos_backend
      endpoints:
        - lb_endpoints:
            - endpoint:
                address:
                  socket_address:
                    address: chronos.odell.com
                    port_value: 8080
```

### Step 6: Commit and Push Changes

Commit the configuration changes to git and push to the remote repository:

```bash
git add vault/policy.hcl vault/vault-agent.hcl envoy.yaml
git commit -m "Add TLS service for <service-name>"
git push
```

**What this does:**
- Commits the three configuration files that were modified
- Pushes changes to remote repository
- Triggers deployment pipeline (if configured)

**Note:** The deployment must pull these changes before the services can use the new configuration.

### Step 7: Deploy Changes

Restart the services to apply the configuration changes:

```bash
make stop
make start
```

**What happens:**
1. Docker Compose stops vault-agent and envoy containers
2. Services restart with new configuration
3. Vault Agent authenticates and fetches certificates for all services
4. Render script creates certificate files and SDS config
5. Envoy loads new filter chain and cluster configuration

**Expected startup sequence:**
1. Vault Agent starts, authenticates, and runs templates
2. Certificates are fetched and rendered to `/vault/certs/`
3. Envoy starts and loads certificates via SDS
4. Envoy health check passes

### Step 8: Verify Certificate Fetching

Check that Vault Agent successfully fetched and rendered certificates:

```bash
# Check raw JSON certificate data
docker exec vault-agent ls -la /vault/certs/<service-name>*

# Expected files:
# <service-name>.json              # Raw Vault response
# <service-name>.leaf.pem          # Server certificate only
# <service-name>.issuing_ca.pem    # Issuing CA certificate
# <service-name>.fullchain.pem     # Full chain (leaf + CA)
# <service-name>.key               # Private key (600 permissions)
# <service-name>-sds.yaml          # SDS configuration for Envoy
```

**Example (chronos):**
```bash
docker exec vault-agent ls -la /vault/certs/chronos*
```

**Expected output:**
```
-rw-------    1 vault    vault         1675 Jan  5 12:00 chronos.key
-rw-r--r--    1 vault    vault         1234 Jan  5 12:00 chronos.json
-rw-r--r--    1 vault    vault         1310 Jan  5 12:00 chronos.leaf.pem
-rw-r--r--    1 vault    vault         1220 Jan  5 12:00 chronos.issuing_ca.pem
-rw-r--r--    1 vault    vault         2530 Jan  5 12:00 chronos.fullchain.pem
-rw-r--r--    1 vault    vault          456 Jan  5 12:00 chronos-sds.yaml
```

### Step 9: Verify Certificate Files in Envoy

Check that certificates are available in the Envoy container:

```bash
docker exec envoy ls -la /etc/envoy/certs/<service-name>*
```

**Example (chronos):**
```bash
docker exec envoy ls -la /etc/envoy/certs/chronos*
```

**Note:** The `/vault/certs` volume is mounted read-only into Envoy at `/etc/envoy/certs`.

### Step 10: Verify Certificate Details

Inspect the certificate to ensure it has the correct domain and expiration:

```bash
docker exec envoy openssl x509 -in /etc/envoy/certs/<service-name>.fullchain.pem -noout -text
```

**Example (chronos):**
```bash
docker exec envoy openssl x509 -in /etc/envoy/certs/chronos.fullchain.pem -noout -text
```

**Check for:**
- Subject: `CN = chronos.odell.com`
- Subject Alternative Names: `DNS:chronos.odell.com, DNS:localhost`
- Validity dates (should be ~7 days from now with 168h TTL)
- Issuer: Vault intermediate CA

### Step 11: Test HTTPS Endpoint

Test the HTTPS endpoint to verify TLS termination and routing:

```bash
# Using -k to skip certificate verification (if root CA not installed)
curl -k https://<fqdn>/

# Or with proper SNI:
curl -k --resolve <fqdn>:443:<gateway-ip> https://<fqdn>/
```

**Example (chronos):**
```bash
curl -k https://chronos.odell.com/
```

**Expected:** Response from the backend service at port 8080.

### Step 12: Verify SNI Routing

Use OpenSSL to verify SNI-based certificate selection:

```bash
openssl s_client -connect <fqdn>:443 -servername <fqdn> < /dev/null 2>&1 | grep "subject="
```

**Example (chronos):**
```bash
openssl s_client -connect chronos.odell.com:443 -servername chronos.odell.com < /dev/null
```

**Check for:**
- Correct certificate presented (subject should match your service)
- No certificate errors
- SSL handshake completes successfully

### Step 13: Check Envoy Metrics

Verify that Envoy is routing traffic through the new filter chain and cluster:

```bash
# Check for chronos-specific metrics
curl http://localhost:9901/stats | grep <service-name>
```

**Example (chronos):**
```bash
curl http://localhost:9901/stats | grep chronos
```

**Look for metrics like:**
- `cluster.chronos_backend.upstream_cx_active`
- `http.ingress_http_chronos.downstream_cx_total`
- `listener.0.0.0.0_443.ssl.connection_error` (should be 0)

## Automatic Certificate Renewal

Once configured, certificates are automatically managed:

1. **Vault Agent** periodically checks certificate expiration
2. Before TTL expires, Vault Agent requests a new certificate
3. **Render script** is triggered via template `command`
4. New certificate files are written to `/vault/certs/`
5. **SDS configuration** is updated
6. **Envoy** detects SDS file change and hot-reloads certificates
7. No service restart required

**Default renewal:** Certificates with 168h (7 day) TTL renew automatically before expiration.

## Troubleshooting

### Certificate Not Generated

**Symptoms:**
- Files missing in `/vault/certs/<service-name>*`
- Vault Agent logs show errors like "permission denied"

**Resolution:**
```bash
# Check Vault Agent logs
docker compose logs vault-agent | grep -i error

# Common issues:
# - AppRole authentication failed (check VAULT_ROLE_ID and VAULT_SECRET_ID)
# - PKI role doesn't exist (re-run setup script)
# - Policy doesn't grant access to PKI issue path (check vault-agent-vytalmind-api-gateway policy)

# Verify policy includes the service:
vault policy read vault-agent-vytalmind-api-gateway | grep "<service-name>"

# If missing, update vault/policy.hcl and write to Vault:
vault policy write vault-agent-vytalmind-api-gateway vault/policy.hcl

# Restart vault-agent to get new token with updated policy:
docker compose restart vault-agent
```

### Envoy Not Loading Certificates

**Symptoms:**
- Envoy fails to start
- HTTPS requests fail with SSL errors
- Error in logs: `Unexpected SDS secret (expecting X): Y`

**Resolution:**
```bash
# Check Envoy logs for SDS secret name mismatch
docker compose logs envoy | grep -i "Unexpected SDS secret"

# Example error:
# Unexpected SDS secret (expecting vytalmind_search_cert): vytalmind-search_cert

# This means envoy.yaml has the wrong secret name. Fix it to match what's in the SDS file.

# Verify SDS file exists and check the secret name
docker exec vault-agent cat /etc/envoy/certs/<service-name>-sds.yaml

# The 'name:' field in the SDS file is the EXACT string to use in envoy.yaml
# Common issue: Multi-word service names (e.g., vytalmind-search)
#   - SDS file will have: vytalmind-search_cert (hyphen preserved)
#   - Don't use: vytalmind_search_cert (all underscores) ❌

# Check Envoy config dump
curl http://localhost:9901/config_dump | jq '.configs[] | select(.["@type"] | contains("Secret"))'
```

### Wrong Certificate Served

**Symptoms:**
- OpenSSL s_client shows different certificate than expected
- Browser shows wrong domain in certificate

**Resolution:**
```bash
# Check filter chain order in envoy.yaml
# - More specific SNI matches should come BEFORE default filter chain
# - Verify server_names matches your FQDN exactly

# Check which certificate is being served
openssl s_client -connect <fqdn>:443 -servername <fqdn> < /dev/null 2>&1 | openssl x509 -noout -subject
```

### Backend Connection Failures

**Symptoms:**
- 503 Service Unavailable errors
- Envoy logs show upstream connection errors

**Resolution:**
```bash
# Check cluster health
curl http://localhost:9901/clusters | grep <service-name>_backend

# Verify backend is reachable from Envoy container
docker exec envoy ping -c 2 <backend-address>
docker exec envoy nc -zv <backend-address> <backend-port>

# Check cluster configuration in config dump
curl http://localhost:9901/config_dump | jq '.configs[] | select(.["@type"] | contains("Cluster"))'
```

## Rollback Procedure

If issues occur, rollback the changes:

1. **Remove filter chain** from [envoy.yaml](../envoy.yaml)
2. **Remove cluster** from [envoy.yaml](../envoy.yaml)
3. **Remove template** from [vault/vault-agent.hcl](../vault/vault-agent.hcl)
4. **Restart services:**
   ```bash
   make stop
   make start
   ```

**Optional:** Remove Vault resources (only if service won't be added back):
```bash
vault delete pki-intermediate/roles/<service-name>
vault policy delete vault-agent-<service-name>
vault delete auth/approle/role/<service-name>
```

## Reference Files

- [vault/policy.hcl](../vault/policy.hcl) - Lines 11-14 (chronos PKI issue path)
- [envoy.yaml](../envoy.yaml) - Lines 55-92 (chronos filter chain), 108-120 (chronos cluster)
- [vault/vault-agent.hcl](../vault/vault-agent.hcl) - Lines 40-57 (chronos template)
- [scripts/setup-vault-service.sh](../scripts/setup-vault-service.sh) - Vault setup automation
- [scripts/render-vault-cert.sh](../scripts/render-vault-cert.sh) - Certificate rendering

## Summary Checklist

- [ ] Run setup script: `./scripts/setup-vault-service.sh <service> <fqdn> "localhost" 168h`
- [ ] Update [vault/policy.hcl](../vault/policy.hcl) to add PKI issue path for new service
- [ ] Write policy to Vault: `vault policy write vault-agent-vytalmind-api-gateway vault/policy.hcl`
- [ ] Add Vault Agent template to [vault/vault-agent.hcl](../vault/vault-agent.hcl)
- [ ] Add filter chain to [envoy.yaml](../envoy.yaml)
- [ ] Add backend cluster to [envoy.yaml](../envoy.yaml)
- [ ] Commit and push changes: `git add vault/policy.hcl vault/vault-agent.hcl envoy.yaml && git commit -m "Add TLS service for <service-name>" && git push`
- [ ] Restart services: `make stop && make start`
- [ ] Verify certificates: `docker exec vault-agent ls -la /vault/certs/<service>*`
- [ ] Test HTTPS: `curl -k https://<fqdn>/`
- [ ] Verify SNI: `openssl s_client -connect <fqdn>:443 -servername <fqdn>`
- [ ] Check metrics: `curl http://localhost:9901/stats | grep <service>`
