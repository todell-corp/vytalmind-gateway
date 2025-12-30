#!/bin/bash
# Health check script to verify all services are running correctly

set -e

echo "🏥 VytalMind Gateway Health Check"
echo "=================================="

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

check_service() {
  local name=$1
  local url=$2

  if curl -sf "$url" > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} $name is healthy"
    return 0
  else
    echo -e "${RED}✗${NC} $name is unhealthy"
    return 1
  fi
}

echo ""
echo "Infrastructure Services:"
check_service "Redis" "http://localhost:6379" || true
check_service "Keycloak" "http://localhost:8080/health/ready" || true

echo ""
echo "Envoy Proxies:"
check_service "Edge Envoy" "http://localhost:9901/ready" || true
check_service "Internal Envoy" "http://localhost:9902/ready" || true

echo ""
echo "Observability:"
echo "  Prometheus: https://prometheus.odell.com (external - not checked)"

echo ""
echo "Certificate Status:"
echo "Edge TLS certificate:"
if [ -f edge/certs/server.crt ]; then
  openssl x509 -in edge/certs/server.crt -noout -subject -dates 2>/dev/null || echo -e "${RED}✗${NC} Invalid certificate"
else
  echo -e "${RED}✗${NC} Certificate not found"
fi

echo ""
echo "Internal mTLS certificates:"
if [ -f internal/certs/server.crt ]; then
  openssl x509 -in internal/certs/server.crt -noout -subject -dates 2>/dev/null || echo -e "${RED}✗${NC} Invalid certificate"
else
  echo -e "${RED}✗${NC} Server certificate not found"
fi

echo ""
echo "=================================="
echo "Health check complete!"
