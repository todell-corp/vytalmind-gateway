# VytalMind Gateway Architecture

## Overview

The VytalMind Zero-Trust Gateway implements a dual-layer security architecture that separates external and internal trust boundaries.

## Deployment Modes

### Production Mode (Recommended)

Uses external shared infrastructure services:

```
┌─────────────────────────────────────────────────────────┐
│ External Shared Services (Already Deployed)            │
├─────────────────────────────────────────────────────────┤
│ • Vault (vault.odell.com:8200)    - PKI & Secrets      │
│ • Prometheus (prometheus.odell.com) - Metrics          │
│ • Keycloak (keycloak.odell.com)   - OAuth/JWT          │
│ • OpenTelemetry (otel.odell.com)  - Tracing            │
└─────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│ VytalMind Gateway (This Deployment)                    │
├─────────────────────────────────────────────────────────┤
│ • Edge Envoy      - TLS, JWT validation, routing       │
│ • Internal Envoy  - mTLS authentication                │
│ • Redis           - Rate limiting state                │
└─────────────────────────────────────────────────────────┘
```

**Deploy with:**
```bash
docker compose up -d
```

**What gets deployed:**
- ✅ Edge Envoy
- ✅ Internal Envoy
- ✅ Redis
- ✅ Example backend services
- ❌ Keycloak (uses external)
- ❌ OpenTelemetry (uses external)
- ❌ Vault (uses external)
- ❌ Prometheus (uses external)

### Standalone Mode (Development/Testing)

Deploys all services locally, including shared infrastructure:

```
┌─────────────────────────────────────────────────────────┐
│ All Services Deployed Locally                          │
├─────────────────────────────────────────────────────────┤
│ Core Gateway:                                           │
│ • Edge Envoy      - TLS, JWT validation, routing       │
│ • Internal Envoy  - mTLS authentication                │
│ • Redis           - Rate limiting state                │
│                                                         │
│ Shared Services (Local):                               │
│ • Keycloak        - OAuth/JWT provider                 │
│ • OpenTelemetry   - Tracing collector                  │
│ • Jaeger          - Tracing UI                         │
│                                                         │
│ External (Still Required):                             │
│ • Vault (vault.odell.com:8200)                         │
│ • Prometheus (prometheus.odell.com)                    │
└─────────────────────────────────────────────────────────┘
```

**Deploy with:**
```bash
docker compose -f docker-compose.yml -f docker-compose.shared.yml up -d
```

**What gets deployed:**
- ✅ Everything from production mode
- ✅ Keycloak (local instance)
- ✅ OpenTelemetry Collector (local)
- ✅ Jaeger UI (trace viewer)
- ❌ Vault (still uses external)
- ❌ Prometheus (still uses external)

## Component Responsibilities

### Core Gateway Components (Always Deployed Together)

#### Edge Envoy
- **Purpose**: External-facing gateway handling untrusted traffic
- **Location**: Edge network (172.20.0.0/24)
- **Responsibilities**:
  - TLS termination using Vault PKI certificates
  - JWT/OAuth validation against Keycloak
  - JWT claim extraction (sub, email, roles, groups)
  - Rate limiting using Redis
  - Routing to backends (direct or via Internal Envoy)
  - Traffic splitting and canary deployments
  - Request/response logging
  - Prometheus metrics export
  - OpenTelemetry trace generation

#### Internal Envoy
- **Purpose**: Internal gateway for service-to-service communication
- **Location**: Internal network only (172.21.0.0/24)
- **Responsibilities**:
  - mTLS authentication for internal services
  - Certificate-based service identity (SPIFFE)
  - Routing to internal backend services
  - Request/response logging with client cert details
  - Prometheus metrics export
  - OpenTelemetry trace propagation

#### Redis
- **Purpose**: Distributed rate limiting backend
- **Location**: Edge network (172.20.0.0/24)
- **Responsibilities**:
  - Store rate limit counters
  - Share state across multiple Edge Envoy instances
  - Enable horizontal scaling of Edge Envoy

**Why always deployed together:**
- Redis is required for Edge Envoy rate limiting
- Edge and Internal Envoy form the zero-trust boundary
- Tight coupling between these three components
- No value in deploying them separately

### Shared Infrastructure Services (Optional Local Deployment)

#### Keycloak
- **Purpose**: OAuth 2.0 / OpenID Connect provider
- **Production**: Shared service at keycloak.odell.com
- **Local**: Deployed via docker-compose.shared.yml
- **Why optional**:
  - Multiple applications use the same Keycloak instance
  - User identities are centrally managed
  - Realm configuration is portable
  - Local deployment useful for development/testing

#### OpenTelemetry Collector
- **Purpose**: Distributed tracing aggregation
- **Production**: Shared service at otel.odell.com
- **Local**: Deployed via docker-compose.shared.yml with Jaeger
- **Why optional**:
  - Traces from multiple applications go to same collector
  - Centralized trace analysis and correlation
  - Reduces operational overhead
  - Local deployment useful for debugging

### Always External Services

#### Vault
- **Location**: vault.odell.com:8200
- **Purpose**:
  - PKI certificate authority
  - Secrets management
  - AppRole authentication
- **Why external only**:
  - Critical security infrastructure
  - Shared across all applications
  - Requires HA configuration
  - Already deployed and managed

#### Prometheus
- **Location**: prometheus.odell.com
- **Purpose**:
  - Metrics aggregation and storage
  - Alerting
  - Long-term retention
- **Why external only**:
  - Monitors multiple services
  - Central alerting and dashboards
  - Requires persistent storage
  - Already deployed and managed

## Network Architecture

### Production Mode

```
                    Internet
                       ↓
              ┌────────────────┐
              │  Edge Envoy    │ ← TLS certs from Vault
              │  (443, 9901)   │ ← JWT validation via Keycloak
              └────────┬───────┘
                       │
         ┌─────────────┼─────────────┐
         ↓             ↓             ↓
    ┌────────┐   ┌──────────┐   ┌──────────────┐
    │ Redis  │   │ Backend  │   │ Internal     │
    │        │   │ Simple   │   │ Envoy        │
    └────────┘   └──────────┘   └──────┬───────┘
                                        ↓
                                  ┌──────────┐
                                  │ Backend  │
                                  │ Secure   │
                                  └──────────┘

Edge Network (172.20.0.0/24):
- Edge Envoy, Redis, Backend Simple

Internal Network (172.21.0.0/24):
- Internal Envoy, Backend Secure
- No external access (internal: true)
```

### Standalone Mode

Adds local Keycloak and OTel to edge network:

```
                    Internet
                       ↓
              ┌────────────────┐
              │  Edge Envoy    │
              │  (443, 9901)   │
              └────────┬───────┘
                       │
         ┌─────────────┼─────────────────────┐
         ↓             ↓             ↓       ↓
    ┌────────┐   ┌──────────┐   ┌──────┐  ┌───────┐
    │ Redis  │   │ Backend  │   │ Int. │  │Keycloak
    │        │   │ Simple   │   │Envoy │  │(8080) │
    └────────┘   └──────────┘   └──┬───┘  └───────┘
                                    ↓
                              ┌──────────┐
                              │ Backend  │  ┌────────┐
                              │ Secure   │  │  OTel  │
                              └──────────┘  │ Jaeger │
                                            └────────┘
```

## Certificate Hierarchy

```
Vault (vault.odell.com:8200)
├── Root PKI (pki/)
│   ├── Purpose: Edge TLS certificates
│   ├── TTL: 8760h (1 year)
│   ├── Role: edge-gateway
│   └── Issued to: gateway.vytalmind.local
│
└── Intermediate PKI (pki_int/)
    ├── Purpose: Internal mTLS certificates
    ├── TTL: 720h (30 days)
    ├── Role: internal-service
    ├── SPIFFE URI: spiffe://vytalmind.local/service/*
    └── Issued to: internal-envoy, backend services
```

## Authentication Flows

### External Request (with JWT)

```
1. Client → Edge Envoy (HTTPS/TLS)
2. Edge validates JWT with Keycloak JWKS
3. Lua filter extracts JWT claims
4. Edge adds custom headers (X-JWT-*)
5. Edge routes to backend:
   a. Direct route → Backend Simple
   b. Secure route → Internal Envoy
6. Internal Envoy validates mTLS (if applicable)
7. Backend receives request with JWT claim headers
```

### Service-to-Service (mTLS)

```
1. Service A → Internal Envoy (mTLS)
2. Internal validates client certificate
3. Internal verifies SPIFFE URI SAN
4. Internal logs client cert subject
5. Internal routes to Service B
6. Service B receives request
```

## Scaling Considerations

### Horizontal Scaling

**Edge Envoy:**
- Deploy multiple instances behind load balancer
- Redis ensures rate limit state is shared
- All instances need Vault AppRole credentials
- Stateless - can scale freely

**Internal Envoy:**
- Can deploy multiple instances
- Stateless - can scale freely
- Each instance needs Vault AppRole credentials

**Redis:**
- Single instance sufficient for most use cases
- Can use Redis Cluster for HA
- Or use Redis Sentinel for failover

### Shared Services

**Keycloak (External):**
- Already scaled and managed
- Multiple applications share same instance
- Single source of truth for user identities

**OpenTelemetry (External):**
- Already scaled and managed
- Aggregates traces from all services
- Enables cross-service trace correlation

## Security Boundaries

### Zero-Trust Principles

1. **Edge Network** (172.20.0.0/24)
   - Untrusted external traffic
   - JWT authentication required
   - Rate limiting enforced
   - TLS encryption

2. **Internal Network** (172.21.0.0/24)
   - No external access (`internal: true`)
   - mTLS required for all communication
   - Certificate-based service identity
   - Only accessible via Edge Envoy

3. **Trust Decisions**
   - Edge: JWT signature + claims
   - Internal: Client certificate + SPIFFE URI
   - Never trust network location alone

## When to Use Which Mode

### Use Production Mode When:
- ✅ Deploying to production environment
- ✅ You have external Keycloak and OTel available
- ✅ Multiple applications share infrastructure
- ✅ You want minimal operational overhead
- ✅ You need centralized identity and observability

### Use Standalone Mode When:
- ✅ Local development and testing
- ✅ CI/CD pipeline testing
- ✅ Debugging authentication flows
- ✅ No external services available
- ✅ Complete isolation needed

### Always Required:
- Vault at vault.odell.com:8200 (both modes)
- Prometheus at prometheus.odell.com (both modes)
