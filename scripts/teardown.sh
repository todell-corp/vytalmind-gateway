#!/bin/bash
# Clean shutdown and cleanup script

echo "🛑 Shutting down VytalMind Gateway..."

# Stop all services
docker compose down

# Optional: Remove volumes (commented out for safety)
# echo "🗑️  Removing volumes..."
# docker compose down -v

# Clean up certificates
echo "🧹 Cleaning up certificates..."
rm -f edge/certs/*.crt edge/certs/*.key edge/certs/*.pem
rm -f internal/certs/*.crt internal/certs/*.key internal/certs/*.pem

echo "✅ Teardown complete"
