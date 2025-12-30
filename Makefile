.PHONY: help format format-check lint lint-fix slither mythril 4naly3er aderyn audit cleanup-demo

# Set default target to help
.DEFAULT_GOAL := help

# Glob pattern for Solidity files
SOL_FILES = 'src/**/*.sol'

help: ## Display help information
	@echo "Available commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

lint: ## Check Solidity code with Solhint
	@echo "Linting Solidity files..."
	@npx solhint $(SOL_FILES) || yarn solhint $(SOL_FILES)

lint-fix: ## Fix automatically fixable Solhint issues
	@echo "Fixing linting issues in Solidity files..."
	@npx solhint $(SOL_FILES) --fix || yarn solhint $(SOL_FILES) --fix

slither: ## Run Slither security analysis on all contracts
	@echo "Ensuring security analysis script is executable..."
	@chmod +x script/security_analysis.sh
	@echo "Running Slither security analysis..."
	@./script/security_analysis.sh slither

aderyn: ## Run Aderyn static analysis on all contracts
	@echo "Ensuring security analysis script is executable..."
	@chmod +x script/security_analysis.sh
	@echo "Running Aderyn static analysis..."
	@./script/security_analysis.sh aderyn

audit: ## Run all security analysis tools (Slither and Aderyn)
	@echo "Ensuring security analysis script is executable..."
	@chmod +x script/security_analysis.sh
	@echo "Running comprehensive security audit..."
	@./script/security_analysis.sh all

cleanup-demo: ## Clean up demo files from project directories
	@echo "Ensuring cleanup script is executable..."
	@chmod +x script/cleanup-demo.sh
	@echo "Running cleanup script..."
	@./script/cleanup-demo.sh
