# VytalMind Zero-Trust Gateway Makefile

# Use docker compose (modern syntax)
DOCKER_COMPOSE := docker compose
DOCKER_COMPOSE_STANDALONE := docker compose -f docker-compose.yml -f docker-compose.shared.yml

.PHONY: help setup setup-standalone start start-standalone stop stop-standalone restart logs health clean test vault-setup

help:
	@echo "VytalMind Zero-Trust Gateway"
	@echo "============================"
	@echo ""
	@echo "Deployment Modes:"
	@echo "  Production  - Uses external Keycloak and OTel"
	@echo "  Standalone  - Deploys Keycloak and OTel locally"
	@echo ""
	@echo "Setup Commands:"
	@echo "  make vault-setup       - Setup Vault PKI (run once, required)"
	@echo "  make setup             - Production mode setup"
	@echo "  make setup-standalone  - Standalone mode setup"
	@echo ""
	@echo "Service Management:"
	@echo "  make start             - Start (production mode)"
	@echo "  make start-standalone  - Start (standalone mode)"
	@echo "  make stop              - Stop all services"
	@echo "  make restart           - Restart all services"
	@echo "  make health            - Health check all services"
	@echo "  make clean             - Stop and clean up everything"
	@echo ""
	@echo "Logging:"
	@echo "  make logs              - View all logs"
	@echo "  make logs-edge         - View edge envoy logs"
	@echo "  make logs-internal     - View internal envoy logs"
	@echo ""
	@echo "Testing:"
	@echo "  make test              - Test JWT authentication"
	@echo "  make dev-token         - Get JWT token from Keycloak"
	@echo "  make dev-request       - Make authenticated test request"

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

setup-standalone:
	@chmod +x scripts/*.sh
	@chmod +x edge/config/bootstrap/*.sh
	@chmod +x internal/config/bootstrap/*.sh
	@chmod +x internal/config/*.sh
	@echo "🚀 Setting up in Standalone Mode (with local Keycloak & OTel)..."
	@./scripts/setup.sh standalone

start:
	@echo "Starting in Production Mode..."
	@$(DOCKER_COMPOSE) up -d
	@echo "✅ All services started"

start-standalone:
	@echo "Starting in Standalone Mode (with local Keycloak & OTel)..."
	@$(DOCKER_COMPOSE_STANDALONE) up -d
	@echo "✅ All services started"

stop:
	@echo "Stopping all services..."
	@$(DOCKER_COMPOSE_STANDALONE) down 2>/dev/null || true
	@$(DOCKER_COMPOSE) down
	@echo "✅ All services stopped"

stop-standalone:
	@echo "Stopping all services (standalone mode)..."
	@$(DOCKER_COMPOSE_STANDALONE) down
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
