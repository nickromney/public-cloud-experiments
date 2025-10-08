# Root Makefile for public-cloud-experiments
# Provides common commands across all projects

# Colors
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

.DEFAULT_GOAL := help

##@ Help

.PHONY: help
help: ## Show this help message
	@echo "$(GREEN)Public Cloud Experiments - Common Commands$(NC)"
	@echo ""
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$|^##@.*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; /^##@/ {printf "\n$(YELLOW)%s$(NC)\n", substr($$0, 5)} /^[a-zA-Z_-]+:.*?## / {printf "  $(GREEN)%-25s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "Project-specific Makefiles:"
	@echo "  terraform/claranet-tfwrapper/Makefile"
	@echo "  terraform/terragrunt/Makefile"

##@ Pre-commit and Security

.PHONY: precommit
precommit: ## Run all pre-commit hooks on tracked AND untracked files
	@echo "$(YELLOW)Running all pre-commit hooks...$(NC)"
	@pre-commit run --all-files
	@echo "$(YELLOW)Checking untracked markdown files for emojis...$(NC)"
	@git ls-files --others --exclude-standard '*.md' '*.markdown' | xargs -r .git-hooks/check-emojis.sh || true

.PHONY: precommit-check
precommit-check: ## Run pre-commit hooks (always succeeds, for review)
	@echo "$(YELLOW)Running all pre-commit hooks...$(NC)"
	@pre-commit run --all-files || true

.PHONY: precommit-install
precommit-install: ## Install pre-commit hooks
	@echo "$(YELLOW)Installing pre-commit hooks...$(NC)"
	@pre-commit install
	@echo "$(GREEN)✓ Pre-commit hooks installed$(NC)"

.PHONY: security-setup
security-setup: ## Run security setup script (macOS)
	@./setup-security.sh

.PHONY: gitleaks
gitleaks: ## Run gitleaks secret scanner
	@echo "$(YELLOW)Scanning for secrets with gitleaks...$(NC)"
	@gitleaks detect --verbose

.PHONY: gitleaks-protect
gitleaks-protect: ## Run gitleaks on staged files (pre-commit check)
	@echo "$(YELLOW)Checking staged files for secrets...$(NC)"
	@gitleaks protect --staged --verbose

##@ Formatting and Cleaning

.PHONY: fmt
fmt: ## Format all code (Terraform, Python, etc.)
	@echo "$(YELLOW)Formatting all code...$(NC)"
	@if command -v tofu &>/dev/null; then \
		tofu fmt -recursive terraform/; \
	elif command -v terraform &>/dev/null; then \
		terraform fmt -recursive terraform/; \
	fi
	@if command -v uv &>/dev/null; then \
		for dir in subnet-calculator/api-fastapi-azure-function subnet-calculator/api-fastapi-container-app subnet-calculator/frontend-python-flask; do \
			if [ -d "$$dir" ]; then \
				echo "$(YELLOW)Formatting $$dir...$(NC)"; \
				(cd "$$dir" && uv run black . 2>/dev/null) || true; \
			fi; \
		done; \
	fi
	@echo "$(GREEN)✓ Formatting complete$(NC)"

.PHONY: clean
clean: ## Clean all cached files (.terraform, __pycache__, etc.)
	@echo "$(YELLOW)Cleaning cached files...$(NC)"
	@find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name ".terragrunt-cache" -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@find . -name ".terraform.lock.hcl" -delete 2>/dev/null || true
	@find . -name "*.pyc" -delete 2>/dev/null || true
	@find . -name ".pytest_cache" -type d -exec rm -rf {} + 2>/dev/null || true
	@find . -name ".mypy_cache" -type d -exec rm -rf {} + 2>/dev/null || true
	@find . -name ".ruff_cache" -type d -exec rm -rf {} + 2>/dev/null || true
	@echo "$(GREEN)✓ Cleaned$(NC)"

.PHONY: clean-git
clean-git: ## Remove nested .git directories (dangerous - prompts first)
	@echo "$(YELLOW)Found nested .git directories:$(NC)"
	@find . -name ".git" -type d | grep -v "^\./.git$$" || echo "  None found"
	@echo ""
	@echo "$(YELLOW)WARNING: This will remove nested git repositories!$(NC)"
	@read -p "Continue? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		find . -name ".git" -type d | grep -v "^\./.git$$" | xargs rm -rf; \
		echo "$(GREEN)✓ Removed nested .git directories$(NC)"; \
	else \
		echo "Cancelled"; \
	fi

##@ Python Development

.PHONY: python-test
python-test: ## Run Python tests with pytest in all Python projects
	@echo "$(YELLOW)Running Python tests...$(NC)"
	@for dir in subnet-calculator/api-fastapi-azure-function subnet-calculator/api-fastapi-container-app subnet-calculator/frontend-python-flask; do \
		if [ -d "$$dir" ] && [ -f "$$dir/pyproject.toml" ]; then \
			echo "$(YELLOW)Testing $$dir...$(NC)"; \
			(cd "$$dir" && uv run pytest -v) || exit 1; \
		fi; \
	done
	@echo "$(GREEN)✓ All tests passed$(NC)"

.PHONY: python-lint
python-lint: ## Run Python linting (ruff) in all Python projects
	@echo "$(YELLOW)Running Python linting...$(NC)"
	@for dir in subnet-calculator/api-fastapi-azure-function subnet-calculator/api-fastapi-container-app subnet-calculator/frontend-python-flask; do \
		if [ -d "$$dir" ] && [ -f "$$dir/pyproject.toml" ]; then \
			echo "$(YELLOW)Linting $$dir...$(NC)"; \
			(cd "$$dir" && uv run --with ruff ruff check . 2>/dev/null) || echo "  Skipped (ruff not available)"; \
		fi; \
	done
	@echo "$(GREEN)✓ Linting complete$(NC)"

.PHONY: python-fmt
python-fmt: ## Format Python code with black and ruff
	@echo "$(YELLOW)Formatting Python code...$(NC)"
	@for dir in subnet-calculator/api-fastapi-azure-function subnet-calculator/api-fastapi-container-app subnet-calculator/frontend-python-flask; do \
		if [ -d "$$dir" ] && [ -f "$$dir/pyproject.toml" ]; then \
			echo "$(YELLOW)Formatting $$dir...$(NC)"; \
			(cd "$$dir" && uv run black . 2>/dev/null) || true; \
			(cd "$$dir" && uv run ruff check --fix . 2>/dev/null) || true; \
		fi; \
	done
	@echo "$(GREEN)✓ Python formatting complete$(NC)"

.PHONY: python-check
python-check: python-lint python-test ## Run all Python quality checks (lint + test)
	@echo "$(GREEN)✓ All Python checks passed$(NC)"
