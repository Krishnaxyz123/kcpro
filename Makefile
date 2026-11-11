# Knowledge Base System - Makefile
# Convenience commands for development and deployment

.PHONY: help install dev up down logs test lint format migrate shell clean

# Default target
help:
	@echo "Knowledge Base System - Available Commands"
	@echo ""
	@echo "Development:"
	@echo "  make install     - Install all dependencies"
	@echo "  make dev         - Start development environment"
	@echo "  make up          - Start all services with Docker Compose"
	@echo "  make down        - Stop all services"
	@echo "  make logs        - View service logs"
	@echo "  make shell       - Open shell in backend container"
	@echo ""
	@echo "Database:"
	@echo "  make migrate     - Run database migrations"
	@echo "  make migration   - Create new migration (name=<name>)"
	@echo ""
	@echo "Testing:"
	@echo "  make test        - Run all tests"
	@echo "  make test-unit   - Run unit tests only"
	@echo "  make test-int    - Run integration tests"
	@echo ""
	@echo "Code Quality:"
	@echo "  make lint        - Run linter"
	@echo "  make format      - Format code"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean       - Remove generated files"
	@echo "  make clean-all   - Remove all Docker volumes"

# ============================================================================
# Development
# ============================================================================

install:
	@echo "Installing backend dependencies..."
	cd backend && pip install -e ".[dev]"
	@echo "Installing harvester dependencies..."
	cd harvester && pip install -e ".[dev]"
	@echo "Installing frontend dependencies..."
	cd frontend && npm install
	@echo "Installing Playwright browsers..."
	playwright install chromium

dev:
	@echo "Starting development environment..."
	cd docker && docker-compose up -d db qdrant redis litellm
	@echo "Services started. Run 'make logs' to view logs."
	@echo "Backend: http://localhost:8000"
	@echo "LiteLLM: http://localhost:4000"
	@echo "Qdrant: http://localhost:6333"

up:
	@echo "Starting all services..."
	cd docker && docker-compose up -d
	@echo "All services started."
	@echo "Frontend: http://localhost:3000"
	@echo "Backend: http://localhost:8000"
	@echo "API Docs: http://localhost:8000/docs"

down:
	@echo "Stopping all services..."
	cd docker && docker-compose down

logs:
	cd docker && docker-compose logs -f

logs-backend:
	cd docker && docker-compose logs -f backend

logs-harvester:
	cd docker && docker-compose logs -f harvester

shell:
	cd docker && docker-compose exec backend /bin/bash

shell-db:
	cd docker && docker-compose exec db psql -U postgres -d knowledge_base

# ============================================================================
# Database
# ============================================================================

migrate:
	@echo "Running database migrations..."
	cd backend && alembic upgrade head

migration:
	@if [ -z "$(name)" ]; then \
		echo "Usage: make migration name=<migration_name>"; \
		exit 1; \
	fi
	cd backend && alembic revision --autogenerate -m "$(name)"

migrate-down:
	cd backend && alembic downgrade -1

# ============================================================================
# Testing
# ============================================================================

test:
	@echo "Running all tests..."
	cd backend && pytest tests/ -v --cov=src --cov-report=term-missing
	cd harvester && pytest tests/ -v

test-unit:
	@echo "Running unit tests..."
	cd backend && pytest tests/unit/ -v

test-int:
	@echo "Running integration tests..."
	cd backend && pytest tests/integration/ -v

test-e2e:
	@echo "Running end-to-end tests..."
	cd backend && pytest tests/e2e/ -v

# ============================================================================
# Code Quality
# ============================================================================

lint:
	@echo "Running linter..."
	cd backend && ruff check src/ tests/
	cd harvester && ruff check src/ tests/

lint-fix:
	@echo "Fixing lint issues..."
	cd backend && ruff check --fix src/ tests/
	cd harvester && ruff check --fix src/ tests/

format:
	@echo "Formatting code..."
	cd backend && ruff format src/ tests/
	cd harvester && ruff format src/ tests/

typecheck:
	@echo "Running type checker..."
	cd backend && mypy src/
	cd harvester && mypy src/

# ============================================================================
# Build
# ============================================================================

build:
	@echo "Building Docker images..."
	cd docker && docker-compose build

build-backend:
	cd docker && docker-compose build backend

build-harvester:
	cd docker && docker-compose build harvester

build-frontend:
	cd docker && docker-compose build frontend

# ============================================================================
# Cleanup
# ============================================================================

clean:
	@echo "Removing generated files..."
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".ruff_cache" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".mypy_cache" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete 2>/dev/null || true
	cd frontend && rm -rf .next node_modules 2>/dev/null || true

clean-all: clean
	@echo "Removing Docker volumes..."
	cd docker && docker-compose down -v
	@echo "All volumes removed."

# ============================================================================
# Production
# ============================================================================

deploy-check:
	@echo "Checking deployment requirements..."
	@test -f .env || (echo "ERROR: .env file not found. Copy .env.example to .env" && exit 1)
	@echo "All checks passed!"
