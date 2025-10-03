# Root Makefile for public-cloud-experiments
# Provides common commands across all projects

# Colors
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help message
	@echo "$(GREEN)Public Cloud Experiments - Common Commands$(NC)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "Project-specific Makefiles:"
	@echo "  terraform/claranet-tfwrapper/Makefile"
	@echo "  terraform/terragrunt/Makefile"

.PHONY: precommit
precommit: ## Run all pre-commit hooks (strict - fails on errors)
	@echo "$(YELLOW)Running all pre-commit hooks...$(NC)"
	@pre-commit run --all-files

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

.PHONY: fmt
fmt: ## Format all code (Terraform, Python, etc.)
	@echo "$(YELLOW)Formatting all code...$(NC)"
	@if command -v tofu &>/dev/null; then \
		tofu fmt -recursive terraform/; \
	elif command -v terraform &>/dev/null; then \
		terraform fmt -recursive terraform/; \
	fi
	@echo "$(GREEN)✓ Formatting complete$(NC)"

.PHONY: clean
clean: ## Clean all cached files (.terraform, .terragrunt-cache, __pycache__)
	@echo "$(YELLOW)Cleaning cached files...$(NC)"
	@find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name ".terragrunt-cache" -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@find . -name ".terraform.lock.hcl" -delete 2>/dev/null || true
	@find . -name "*.pyc" -delete 2>/dev/null || true
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
