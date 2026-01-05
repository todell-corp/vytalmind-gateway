# VytalMind Gateway Makefile

DOCKER_COMPOSE := docker compose

.PHONY: help start stop logs health clean

help:
	@echo "VytalMind Gateway"
	@echo "================="
	@echo ""
	@echo "Commands:"
	@echo "  make start   - Start gateway services"
	@echo "  make stop    - Stop all services"
	@echo "  make logs    - View envoy logs"
	@echo "  make health  - Check health endpoint"
	@echo "  make clean   - Stop and remove volumes"

start:
	@echo "Starting gateway..."
	@$(DOCKER_COMPOSE) up -d
	@echo "✅ Gateway started"

stop:
	@echo "Stopping gateway..."
	@$(DOCKER_COMPOSE) down
	@echo "✅ Gateway stopped"

logs:
	@$(DOCKER_COMPOSE) logs -f envoy

health:
	@echo "Checking gateway health..."
	@curl -f -k https://localhost:443/health && echo " ✅ Health check passed" || echo " ❌ Health check failed"

clean:
	@echo "Cleaning up..."
	@$(DOCKER_COMPOSE) down -v
	@echo "✅ Cleanup complete"
