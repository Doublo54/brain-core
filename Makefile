# OpenClaw Gateway — Development Makefile
#
# Convenience targets for local development with docker-compose.dev.yml
#
# Usage:
#   make          Show this help
#   make build    Build gateway and sandbox images
#   make up       Start dev stack
#   make down     Stop dev stack
#   make shell    Open shell in gateway container
#   make logs     Tail gateway logs
#   make test     Run orchestration integration tests inside gateway

.PHONY: help build build-gateway build-sandbox up down shell logs ps clean validate test test-approval telegram-session

# --env-file is required because docker compose resolves ${} interpolation
# from the compose file's directory (docker/), not the working directory.
# Without it, variables from .env are loaded into the container (via env_file)
# but the compose-level interpolation can't find them for defaults/overrides.
COMPOSE := docker compose --env-file .env -f docker/docker-compose.dev.yml

# Default target: show help
help:
	@echo "OpenClaw Gateway — Development Targets"
	@echo ""
	@echo "  make build          Build gateway and sandbox images"
	@echo "  make build-gateway  Build gateway image only"
	@echo "  make build-sandbox  Build sandbox image only (cached)"
	@echo "  make up             Start dev compose stack"
	@echo "  make down           Stop dev compose stack and remove containers"
	@echo "  make shell          Open shell in running gateway container"
	@echo "  make logs           Tail gateway logs"
	@echo "  make ps             Show running services"
	@echo "  make clean          Remove volumes and images"
	@echo "  make validate       Validate compose file syntax"
	@echo "  make test           Run orchestration integration tests"
	@echo "  make test-approval  Run approval gate integration tests"
	@echo "  make telegram-session  Generate Telegram StringSession for .env"
	@echo ""

# Build both gateway and sandbox images
build:
	$(COMPOSE) build

# Build gateway image only
build-gateway:
	$(COMPOSE) build openclaw

# Build sandbox image only (and cache)
build-sandbox:
	$(COMPOSE) build sandbox-builder

# Start dev compose stack
up:
	$(COMPOSE) up -d

# Stop dev compose stack and remove containers
down:
	$(COMPOSE) down

# Open shell in running gateway container
shell:
	$(COMPOSE) exec openclaw bash

# Tail gateway logs
logs:
	$(COMPOSE) logs -f openclaw

# Show running services
ps:
	$(COMPOSE) ps

# Remove volumes and images
clean:
	$(COMPOSE) down -v
	docker rmi openclaw-gateway:local openclaw-sandbox:bookworm-slim 2>/dev/null || true

# Validate compose file syntax
validate:
	$(COMPOSE) config --quiet

# Run orchestration integration tests inside the gateway container
test:
	$(COMPOSE) exec openclaw bash /opt/scripts/orchestration/test-orchestrator.sh

# Run approval gate integration tests inside the gateway container
test-approval:
	$(COMPOSE) exec openclaw bash /opt/scripts/orchestration/test-approval-gate.sh

# Generate a Telegram StringSession for the telegramuser plugin
telegram-session:
	node scripts/generate-telegram-session.mjs
