#!/bin/bash
# Initial setup script for the zero-trust gateway

set -e

# Check if standalone mode
STANDALONE_MODE=false
if [ "$1" = "standalone" ]; then
  STANDALONE_MODE=true
  echo "🚀 Setting up VytalMind Zero-Trust Gateway (Standalone Mode)..."
  echo "   This will deploy Keycloak and OpenTelemetry locally."
else
  echo "🚀 Setting up VytalMind Zero-Trust Gateway (Production Mode)..."
  echo "   Using external Keycloak and OpenTelemetry services."
fi

# Check prerequisites
command -v docker >/dev/null 2>&1 || { echo "❌ Docker is required but not installed."; exit 1; }

# Use docker compose (modern syntax)
if [ "$STANDALONE_MODE" = true ]; then
  DOCKER_COMPOSE="docker compose -f docker-compose.yml -f docker-compose.shared.yml"
else
  DOCKER_COMPOSE="docker compose"
fi

# Create .env from example if it doesn't exist
if [ ! -f .env ]; then
  echo "📝 Creating .env file from template..."
  cp .env.example .env
  echo "⚠️  IMPORTANT: You must update .env with Vault AppRole credentials!"
  echo "   Run the Vault PKI setup script first:"
  echo "   export VAULT_TOKEN=<your-vault-admin-token>"
  echo "   ./infrastructure/vault/scripts/setup-pki.sh"
  echo ""
  echo "   Then update .env with the AppRole IDs that are printed."
  if [ "$STANDALONE_MODE" = false ]; then
    echo ""
    echo "   For production mode, also update:"
    echo "   - KEYCLOAK_URL (external Keycloak URL)"
    echo "   - OTEL_EXPORTER_OTLP_ENDPOINT (external OTel URL)"
  fi
  echo ""
  read -p "Press Enter after you've updated .env with your configuration..."
fi

# Create necessary directories
echo "📁 Creating required directories..."
mkdir -p edge/certs edge/logs
mkdir -p internal/certs internal/logs

# Set proper permissions
chmod 700 edge/certs internal/certs

# Pull required images
echo "📦 Pulling Docker images..."
$DOCKER_COMPOSE pull

# Start infrastructure services first
echo "🏗️  Starting infrastructure services..."
if [ "$STANDALONE_MODE" = true ]; then
  echo "   Starting Redis, Keycloak, and OTel Collector..."
  $DOCKER_COMPOSE up -d redis keycloak otel-collector
else
  echo "   Starting Redis (using external Keycloak and OTel)..."
  $DOCKER_COMPOSE up -d redis
fi

# Wait for services to be healthy
echo "⏳ Waiting for services to be ready..."
if [ "$STANDALONE_MODE" = true ]; then
  sleep 30  # More time needed for Keycloak to start
else
  sleep 15
fi

# Start Envoy proxies
echo "🌐 Starting Envoy proxies..."
$DOCKER_COMPOSE up -d edge-envoy internal-envoy

# Start example backends
echo "🎯 Starting example backend services..."
$DOCKER_COMPOSE up -d backend-simple backend-secure

echo ""
echo "✅ Setup complete!"
echo ""
echo "🔗 Access points:"
echo "   Edge Envoy (HTTPS):     https://localhost:443"
echo "   Edge Admin:             http://localhost:9901"
echo "   Internal Admin:         http://localhost:9902"

if [ "$STANDALONE_MODE" = true ]; then
  echo "   Keycloak:               http://localhost:8080"
  echo "   OTel Collector:         http://localhost:4317"
  echo "   Jaeger UI:              http://localhost:16686"
else
  echo "   Keycloak:               (external - see .env KEYCLOAK_URL)"
  echo "   OTel Collector:         (external - see .env OTEL_EXPORTER_OTLP_ENDPOINT)"
fi

echo "   Prometheus:             https://prometheus.odell.com (external)"
echo ""
echo "📚 Next steps:"
echo "   1. Verify all services are healthy: ./scripts/health-check.sh"
echo "   2. Get JWT token from Keycloak: make dev-token"
echo "   3. Test authenticated request: make dev-request"
echo ""
