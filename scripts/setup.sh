#!/bin/bash
# Initial setup script for the zero-trust gateway

set -e

echo "🚀 Setting up VytalMind Zero-Trust Gateway..."

# Check prerequisites
command -v docker >/dev/null 2>&1 || { echo "❌ Docker is required but not installed."; exit 1; }

# Use docker compose (modern syntax)
DOCKER_COMPOSE="docker compose"

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
  echo ""
  read -p "Press Enter after you've updated .env with your Vault credentials..."
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
$DOCKER_COMPOSE up -d redis keycloak

# Wait for services to be healthy
echo "⏳ Waiting for services to be ready..."
sleep 15

# Start Envoy proxies
echo "🌐 Starting Envoy proxies..."
$DOCKER_COMPOSE up -d edge-envoy internal-envoy

# Start observability stack
echo "📊 Starting observability stack..."
$DOCKER_COMPOSE up -d otel-collector

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
echo "   Keycloak:               http://localhost:8080"
echo "   Prometheus:             https://prometheus.odell.com (external)"
echo ""
echo "📚 Next steps:"
echo "   1. Verify all services are healthy: ./scripts/health-check.sh"
echo "   2. Get JWT token from Keycloak: make dev-token"
echo "   3. Test authenticated request: make dev-request"
echo ""
