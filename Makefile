# VytalMind Zero-Trust Gateway Makefile

# Use docker compose (modern syntax)
DOCKER_COMPOSE := docker compose

.PHONY: help setup start stop restart logs health clean test vault-setup

help:
	@echo "VytalMind Zero-Trust Gateway"
	@echo "============================"
	@echo ""
	@echo "Available commands:"
	@echo "  make setup         - Initial setup and configuration"
	@echo "  make vault-setup   - Setup Vault PKI (requires VAULT_TOKEN)"
	@echo "  make start         - Start all services"
	@echo "  make stop          - Stop all services"
	@echo "  make restart       - Restart all services"
	@echo "  make logs          - View logs (all services)"
	@echo "  make logs-edge     - View edge envoy logs"
	@echo "  make logs-internal - View internal envoy logs"
	@echo "  make health        - Run health checks"
	@echo "  make test          - Test JWT authentication"
	@echo "  make dev-token     - Get JWT token from Keycloak"
	@echo "  make dev-request   - Make authenticated test request"
	@echo "  make clean         - Clean up all resources"

vault-setup:
	@echo "Setting up Vault PKI..."
	@if [ -z "$$VAULT_TOKEN" ]; then \
		echo "ERROR: VAULT_TOKEN environment variable not set"; \
		echo "Please set your Vault admin token:"; \
		echo "  export VAULT_TOKEN=<your-vault-token>"; \
		exit 1; \
	fi
	@chmod +x infrastructure/vault/scripts/setup-pki.sh
	@./infrastructure/vault/scripts/setup-pki.sh

setup:
	@chmod +x scripts/*.sh
	@chmod +x edge/config/bootstrap/*.sh
	@chmod +x internal/config/bootstrap/*.sh
	@chmod +x internal/config/*.sh
	@./scripts/setup.sh

start:
	@$(DOCKER_COMPOSE) up -d
	@echo "✅ All services started"

stop:
	@$(DOCKER_COMPOSE) down
	@echo "✅ All services stopped"

restart:
	@$(DOCKER_COMPOSE) restart
	@echo "✅ All services restarted"

logs:
	@$(DOCKER_COMPOSE) logs -f

logs-edge:
	@$(DOCKER_COMPOSE) logs -f edge-envoy

logs-internal:
	@$(DOCKER_COMPOSE) logs -f internal-envoy

health:
	@chmod +x scripts/health-check.sh
	@./scripts/health-check.sh

clean:
	@chmod +x scripts/teardown.sh
	@./scripts/teardown.sh
	@echo "✅ Cleanup complete"

# Development helpers
dev-token:
	@echo "Getting Keycloak access token..."
	@curl -s -X POST http://localhost:8080/realms/vytalmind/protocol/openid-connect/token \
		-H "Content-Type: application/x-www-form-urlencoded" \
		-d "client_id=edge-gateway" \
		-d "client_secret=your-client-secret-change-in-production" \
		-d "username=testuser" \
		-d "password=password123" \
		-d "grant_type=password" | jq -r '.access_token'

dev-request:
	@echo "Making authenticated request to edge gateway..."
	@TOKEN=$$(make -s dev-token) && \
		curl -k -H "Authorization: Bearer $$TOKEN" https://localhost:443/api/simple/ && echo

test: dev-request
	@echo "✅ Test complete"
