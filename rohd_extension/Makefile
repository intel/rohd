# Makefile for the ROHD VS Code Extension (rohd_extension)
#
# Targets:
#   compile        - Compile TypeScript sources to out/
#   install        - Compile and install to remote VS Code Server (default)
#   install-local  - Compile and install to local VS Code
#   install-remote - Compile and install to remote VS Code Server
#   package        - Build and verify a Marketplace-ready VSIX
#   verify-vsix    - Verify the current Marketplace VSIX
#   clean          - Remove compiled output and packaged .vsix files
#   real-clean     - clean + remove node_modules, lock files, .dart_tool
#   help           - Show this help

ROOT := $(shell pwd)
NODE ?= node
NPM ?= npm
TS_SOURCES := $(shell find $(ROOT)/src -name '*.ts' 2>/dev/null)

# The extension Pub manifest is the authoritative release version.
PUBSPEC_VERSION := $(shell awk '$$1 == "version:" { print $$2; exit }' "$(ROOT)/pubspec.yaml")

# Read Marketplace identity from package.json.
PKG_NAME := $(shell $(NODE) -p "require('./package.json').name")
PKG_VERSION := $(PUBSPEC_VERSION)
PKG_PUBLISHER := $(shell $(NODE) -p "require('./package.json').publisher")
VSIX := $(ROOT)/build/$(PKG_PUBLISHER).$(PKG_NAME)-$(PKG_VERSION).vsix
VERIFY_VSIX := $(ROOT)/tool/verify_marketplace_vsix.sh
VERIFY_EXTENSION_PACK := $(ROOT)/tool/verify_extension_pack.sh

# VS Code Server extension directory (remote dev container)
REMOTE_EXT_DIR := $(HOME)/.vscode-server/extensions/$(PKG_PUBLISHER).$(PKG_NAME)-$(PKG_VERSION)
# Local VS Code extension directory
LOCAL_EXT_DIR := $(HOME)/.vscode/extensions/$(PKG_PUBLISHER).$(PKG_NAME)-$(PKG_VERSION)

# Stamp file to track last successful compile
COMPILE_STAMP := out/.compile-stamp

.PHONY: all help compile package sync-version verify-vsix verify-extension-version verify-extension-pack install install-local install-remote clean real-clean

all: install

help:
	@echo "ROHD VS Code Extension - Build Targets"
	@echo ""
	@echo "  compile        - Compile TypeScript to out/"
	@echo "  package        - Build and verify a Marketplace-ready VSIX"
	@echo "  sync-version   - Synchronize package.json and package-lock.json from pubspec.yaml"
	@echo "  verify-vsix    - Verify the current Marketplace VSIX"
	@echo "  verify-extension-pack - Verify declared viewer extension-pack identity"
	@echo "  install        - Compile and install to remote server (default)"
	@echo "  install-local  - Compile and install to local VS Code"
	@echo "  install-remote - Compile and install to remote VS Code Server"
	@echo "  clean          - Remove compiled output and .vsix files"
	@echo "  real-clean     - clean + node_modules, lock files, .dart_tool"
	@echo ""
	@echo "Extension: $(PKG_PUBLISHER).$(PKG_NAME) v$(PKG_VERSION)"
	@echo "VSIX:      $(VSIX)"
	@echo "Remote:    $(REMOTE_EXT_DIR)"

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

# Install npm dependencies (including TypeScript) if missing or out of date
node_modules: package.json package-lock.json
	@echo "Installing npm dependencies..."
	@$(NPM) ci
	@touch node_modules

# ---------------------------------------------------------------------------
# Compile
# ---------------------------------------------------------------------------

$(COMPILE_STAMP): $(TS_SOURCES) tsconfig.json package.json node_modules
	@echo "Compiling TypeScript..."
	@$(NPM) run compile
	@touch $(COMPILE_STAMP)

compile: $(COMPILE_STAMP)

# ---------------------------------------------------------------------------
# Marketplace packaging
# ---------------------------------------------------------------------------

verify-extension-version:
	@pubspec_version="$(PUBSPEC_VERSION)"; \
	manifest_version="$$($(NODE) -p "require('./package.json').version")"; \
	lock_version="$$($(NODE) -p "require('./package-lock.json').version")"; \
	lock_root_version="$$($(NODE) -p "require('./package-lock.json').packages[''].version")"; \
	lock_name="$$($(NODE) -p "require('./package-lock.json').packages[''].name")"; \
	manifest_name="$$($(NODE) -p "require('./package.json').name")"; \
	publisher="$$($(NODE) -p "require('./package.json').publisher")"; \
	if [ -z "$$pubspec_version" ]; then \
		echo "error: Unable to read version from pubspec.yaml."; \
		exit 1; \
	elif [ "$$pubspec_version" != "$$manifest_version" ] || \
	   [ "$$pubspec_version" != "$$lock_version" ] || \
	   [ "$$pubspec_version" != "$$lock_root_version" ] || \
	   [ "$$manifest_name" != "$$lock_name" ]; then \
		echo "error: Pub and VS Code extension versions do not match."; \
		echo "  pubspec.yaml:      $$pubspec_version"; \
		echo "  package.json:      $$manifest_name $$manifest_version"; \
		echo "  package-lock.json: $$lock_name $$lock_version (root $$lock_root_version)"; \
		exit 1; \
	elif [ "$$publisher" != "intel-corporation" ]; then \
		echo "error: Marketplace publisher must be intel-corporation, got $$publisher."; \
		exit 1; \
	fi; \
	echo "Pub and VS Code extension version $$pubspec_version verified for $$publisher.$$manifest_name."

sync-version:
	@if [ -z "$(PUBSPEC_VERSION)" ]; then \
		echo "error: Unable to read version from pubspec.yaml."; \
		exit 1; \
	fi
	@cd "$(ROOT)" && $(NPM) version "$(PUBSPEC_VERSION)" --no-git-tag-version --allow-same-version
	@echo "Synchronized VS Code extension version $(PUBSPEC_VERSION) from pubspec.yaml."

verify-extension-pack:
	@bash "$(VERIFY_EXTENSION_PACK)"

$(VSIX): $(TS_SOURCES) pubspec.yaml package.json package-lock.json .vscodeignore README.md LICENSE CHANGELOG.md $(VERIFY_VSIX) $(VERIFY_EXTENSION_PACK) node_modules | verify-extension-version verify-extension-pack
	@echo "Packaging Marketplace VSIX..."
	@mkdir -p "$(dir $@)"
	@rm -f "$@"
	@$(NPM) run package -- --out "$@"
	@bash "$(VERIFY_VSIX)" "$@"

package: $(VSIX)
	@bash "$(VERIFY_VSIX)" "$(VSIX)"

verify-vsix: package

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------

install-remote: compile
	@if [ -d "$(REMOTE_EXT_DIR)" ]; then \
		echo "Installing to $(REMOTE_EXT_DIR)/out/..."; \
		cp out/*.js out/*.js.map "$(REMOTE_EXT_DIR)/out/"; \
		cp package.json "$(REMOTE_EXT_DIR)/package.json"; \
		mkdir -p "$(REMOTE_EXT_DIR)/resources"; \
		cp resources/* "$(REMOTE_EXT_DIR)/resources/"; \
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
		cp package.json "$(LOCAL_EXT_DIR)/package.json"; \
		mkdir -p "$(LOCAL_EXT_DIR)/resources"; \
		cp resources/* "$(LOCAL_EXT_DIR)/resources/"; \
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
	@rm -rf build/
	@rm -f *.vsix

real-clean: clean
	@echo "Removing node_modules and Dart build artifacts..."
	@rm -rf node_modules/
	@rm -rf dart/.dart_tool/
	@rm -f dart/pubspec.lock
