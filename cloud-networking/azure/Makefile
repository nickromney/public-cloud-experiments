.PHONY: help test test-unit test-integration test-verbose test-watch install-bats clean quality lint

# Default target
help:
	@echo "Azure Networking Scripts - Test Targets"
	@echo ""
	@echo "Available targets:"
	@echo "  make test              - Run all unit tests (mocked, no Azure required)"
	@echo "  make test-unit         - Same as 'make test' - unit tests with mocks"
	@echo "  make test-integration  - Run integration tests (requires Azure login)"
	@echo "  make test-verbose      - Run tests with verbose output"
	@echo "  make test-watch        - Watch for changes and re-run tests"
	@echo "  make install-bats      - Install BATS and required dependencies"
	@echo "  make clean             - Clean test artifacts and temporary files"
	@echo "  make lint              - Run shellcheck on all scripts"
	@echo "  make quality           - Run lint + test-unit"
	@echo ""
	@echo "Pre-commit validation:"
	@echo "  cd ../.. && make precommit  - Run full pre-commit checks (from repo root)"
	@echo ""
	@echo "Test files:"
	@echo "  tests/test_validation.bats           - Script quality validation"
	@echo "  tests/test_resource_scripts.bats     - Resource script tests"
	@echo "  tests/test_orchestrator_scripts.bats - Orchestrator script tests"
	@echo "  tests/test_command_construction.bats - Command construction tests"
	@echo "  tests/test_error_handling.bats       - Error handling tests"

# Run all unit tests (default test target)
test: test-unit

# Unit tests with mocked Azure CLI (no Azure login required)
test-unit:
	@echo "Running unit tests (mocked Azure CLI)..."
	@if ! command -v bats &> /dev/null; then \
		echo "ERROR: BATS is not installed. Run 'make install-bats' first."; \
		exit 1; \
	fi
	cd tests && bats test_validation.bats \
		test_resource_scripts.bats \
		test_orchestrator_scripts.bats \
		test_command_construction.bats \
		test_error_handling.bats

# Integration tests with real Azure (requires az login)
test-integration:
	@echo "Running integration tests (requires Azure login)..."
	@if ! az account show &> /dev/null; then \
		echo "ERROR: Not logged in to Azure. Run 'az login' first."; \
		exit 1; \
	fi
	@echo "WARNING: Integration tests will create real Azure resources."
	@echo "Make sure you are using a sandbox or test subscription."
	@read -p "Continue? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	cd tests && BATS_INTEGRATION=true bats test_*.bats

# Run tests with verbose output for debugging
test-verbose:
	@echo "Running tests with verbose output..."
	cd tests && bats --verbose-run --print-output-on-failure test_*.bats

# Watch mode - re-run tests on file changes (requires entr)
test-watch:
	@if ! command -v entr &> /dev/null; then \
		echo "ERROR: entr is not installed."; \
		echo "Install with: brew install entr"; \
		exit 1; \
	fi
	@echo "Watching for changes... (Ctrl+C to stop)"
	@find . -name "*.sh" -o -name "*.bats" -o -name "*.bash" | entr -c make test-unit

# Install BATS and dependencies
install-bats:
	@echo "Installing BATS and dependencies..."
	@if ! command -v brew &> /dev/null; then \
		echo "ERROR: Homebrew is not installed."; \
		echo "Install from: https://brew.sh"; \
		exit 1; \
	fi
	brew install bats-core
	@echo ""
	@echo "Installing BATS support libraries..."
	@mkdir -p tests/test_helper
	@if [ ! -d tests/test_helper/bats-support ]; then \
		git clone https://github.com/bats-core/bats-support tests/test_helper/bats-support; \
		rm -rf tests/test_helper/bats-support/.git; \
		echo "bats-support installed (without .git)"; \
	else \
		echo "bats-support already installed"; \
	fi
	@if [ ! -d tests/test_helper/bats-assert ]; then \
		git clone https://github.com/bats-core/bats-assert tests/test_helper/bats-assert; \
		rm -rf tests/test_helper/bats-assert/.git; \
		echo "bats-assert installed (without .git)"; \
	else \
		echo "bats-assert already installed"; \
	fi
	@echo ""
	@echo "BATS installation complete!"
	@echo "Run 'make test' to run unit tests"

# Clean test artifacts
clean:
	@echo "Cleaning test artifacts..."
	@rm -rf tests/test_helper/bats-support/.git
	@rm -rf tests/test_helper/bats-assert/.git
	@find tests -name "*.tmp" -delete
	@find tests -name "*.bak" -delete
	@echo "Clean complete"

# Run a specific test file
# Usage: make test-file FILE=test_validation
test-file:
	@if [ -z "$(FILE)" ]; then \
		echo "ERROR: FILE parameter required"; \
		echo "Usage: make test-file FILE=test_validation"; \
		exit 1; \
	fi
	cd tests && bats $(FILE).bats

# Show test coverage summary
test-summary:
	@echo "Test Coverage Summary"
	@echo "===================="
	@echo ""
	@echo "Validation Tests:"
	@grep -c "^@test" tests/test_validation.bats | xargs -I {} echo "  {} tests"
	@echo ""
	@echo "Resource Script Tests:"
	@grep -c "^@test" tests/test_resource_scripts.bats | xargs -I {} echo "  {} tests"
	@echo ""
	@echo "Orchestrator Tests:"
	@grep -c "^@test" tests/test_orchestrator_scripts.bats | xargs -I {} echo "  {} tests"
	@echo ""
	@echo "Command Construction Tests:"
	@grep -c "^@test" tests/test_command_construction.bats | xargs -I {} echo "  {} tests"
	@echo ""
	@echo "Error Handling Tests:"
	@grep -c "^@test" tests/test_error_handling.bats | xargs -I {} echo "  {} tests"
	@echo ""
	@echo "Total Tests:"
	@grep -c "^@test" tests/test_*.bats | awk '{s+=$$1} END {print "  " s " tests"}'

# Validate all shell scripts with shellcheck
lint:
	@echo "Running shellcheck on all scripts..."
	@shellcheck *.sh || true
	@echo "Shellcheck complete"

# Run all quality checks (local only - for full pre-commit run 'make precommit' from repo root)
quality: lint test-unit
	@echo "All quality checks complete!"
	@echo ""
	@echo "NOTE: Run 'cd ../.. && make precommit' for full pre-commit validation"
