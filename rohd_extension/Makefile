# Makefile for the ROHD VS Code Extension (rohd_extension)
#
# Targets:
#   compile        - Compile TypeScript sources to out/
#   install        - Compile and install to remote VS Code Server (default)
#   install-local  - Compile and install to local VS Code
#   install-remote - Compile and install to remote VS Code Server
#   clean          - Remove compiled output and packaged .vsix files
#   real-clean     - clean + remove node_modules, lock files, .dart_tool
#   help           - Show this help

ROOT := $(shell pwd)
TS_SOURCES := $(shell find $(ROOT)/src -name '*.ts' 2>/dev/null)

# Read name/version from package.json
PKG_NAME := $(shell node -p "require('./package.json').name")
PKG_VERSION := $(shell node -p "require('./package.json').version")
PKG_PUBLISHER := $(shell node -p "require('./package.json').publisher")

# VS Code Server extension directory (remote dev container)
REMOTE_EXT_DIR := $(HOME)/.vscode-server/extensions/$(PKG_PUBLISHER).$(PKG_NAME)-$(PKG_VERSION)
# Local VS Code extension directory
LOCAL_EXT_DIR := $(HOME)/.vscode/extensions/$(PKG_PUBLISHER).$(PKG_NAME)-$(PKG_VERSION)

# Stamp file to track last successful compile
COMPILE_STAMP := out/.compile-stamp

.PHONY: all help compile install install-local install-remote clean real-clean

all: install

help:
	@echo "ROHD VS Code Extension - Build Targets"
	@echo ""
	@echo "  compile        - Compile TypeScript to out/"
	@echo "  install        - Compile and install to remote server (default)"
	@echo "  install-local  - Compile and install to local VS Code"
	@echo "  install-remote - Compile and install to remote VS Code Server"
	@echo "  clean          - Remove compiled output and .vsix files"
	@echo "  real-clean     - clean + node_modules, lock files, .dart_tool"
	@echo ""
	@echo "Extension: $(PKG_PUBLISHER).$(PKG_NAME) v$(PKG_VERSION)"
	@echo "Remote:    $(REMOTE_EXT_DIR)"

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

# Install npm dependencies (including TypeScript) if missing or out of date
node_modules: package.json
	@echo "Installing npm dependencies..."
	@npm install
	@touch node_modules

# ---------------------------------------------------------------------------
# Compile
# ---------------------------------------------------------------------------

$(COMPILE_STAMP): $(TS_SOURCES) tsconfig.json package.json node_modules
	@echo "Compiling TypeScript..."
	@npx tsc -p ./
	@touch $(COMPILE_STAMP)

compile: $(COMPILE_STAMP)

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------

install-remote: compile
	@if [ -d "$(REMOTE_EXT_DIR)" ]; then \
		echo "Installing to $(REMOTE_EXT_DIR)/out/..."; \
		cp out/*.js out/*.js.map "$(REMOTE_EXT_DIR)/out/"; \
		echo "Done. Reload the VS Code window to pick up changes."; \
	else \
		echo "ERROR: Extension not found at $(REMOTE_EXT_DIR)"; \
		echo "Install the extension first via VS Code, then use this target to update."; \
		exit 1; \
	fi

install-local: compile
	@if [ -d "$(LOCAL_EXT_DIR)" ]; then \
		echo "Installing to $(LOCAL_EXT_DIR)/out/..."; \
		cp out/*.js out/*.js.map "$(LOCAL_EXT_DIR)/out/"; \
		echo "Done. Reload the VS Code window to pick up changes."; \
	else \
		echo "ERROR: Extension not found at $(LOCAL_EXT_DIR)"; \
		echo "Install the extension first via VS Code, then use this target to update."; \
		exit 1; \
	fi

install: install-remote

# ---------------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------------

clean:
	@echo "Cleaning compiled output and .vsix files..."
	@rm -rf out/
	@rm -f *.vsix

real-clean: clean
	@echo "Removing node_modules, lock files, and Dart build artifacts..."
	@rm -rf node_modules/
	@rm -f package-lock.json
	@rm -rf dart/.dart_tool/
	@rm -f dart/pubspec.lock
