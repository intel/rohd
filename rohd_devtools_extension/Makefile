# Makefile for ROHD DevTools Extension
# Normal app builds consume prepared viewer packages without building them.

ROOT := $(shell pwd)
WORKSPACE_ROOT := $(abspath $(ROOT)/..)
FLUTTER_WEB_BUILD_ARGS ?=
LOCAL_WIDGETS_DIR := $(ROOT)/../packages/rohd_devtools_widgets
COVERAGE_SCRIPT := $(WORKSPACE_ROOT)/tool/generate_coverage.sh
COVERAGE_VIEW_SCRIPT := $(WORKSPACE_ROOT)/tool/view_coverage.sh

# Source file patterns for dependency tracking
DART_SOURCES := $(shell find lib -name '*.dart' 2>/dev/null)
ASSET_STAGING_INPUTS := scripts/stage_assets.sh scripts/install_viewer_artifacts.sh scripts/resolve_package_root.dart $(wildcard $(WORKSPACE_ROOT)/.dart_tool/package_config.json)

.PHONY: all build-linux build-web clean clean-linux clean-web clean-stamps web web-release web-run web-run-profile help force real-clean extension install-local install-remote test test-integration test-all coverage coverage-view coverage-clean viewer-artifacts

all: linux

# Validate dependency artifacts without generating or compiling them.
viewer-artifacts:
	@bash $(ROOT)/scripts/install_viewer_artifacts.sh

# Run the lightweight cubit and widget tests on the Flutter VM. The extension
# entry point uses `dart:js_interop`, but these tests exercise platform-neutral
# library code and do not require a browser.
# The filter_bank integration test imports the full ROHD simulation stack
# which takes several minutes to DDC-compile — run via `make test-integration`.
test: assets/.staged
	@flutter test test/cubit/basic_cubits_test.dart
	@flutter test test/modules/tree_structure/tree_structure_page_test.dart
	@flutter test test/modules/tree_structure/model_tree_card_test.dart

# Full integration test using the real FilterBank ROHD example and the
# standalone loopback hierarchy, waveform, and design-shell adapters.
test-integration:
	@cd "$(WORKSPACE_ROOT)" && flutter pub get
	@flutter test test/integration/

# Run everything.
test-all: test test-integration

# Generate coverage for this Flutter package, not the repository root.
coverage:
	@bash "$(COVERAGE_SCRIPT)"

# Serve this package's generated coverage report.
coverage-view:
	@bash "$(COVERAGE_VIEW_SCRIPT)"

coverage-clean:
	@rm -rf "$(ROOT)/coverage"

# Stage assets from all widgets - copies their assets to canonical assets/ location
# Each widget contributes its own assets; top-level script merges them.
# Flutter's pubspec.yaml declares assets/ and automatically bundles into:
#  - build/web/assets/ (for web builds)
#  - build/linux/assets/ (for Linux native builds)
# Output marker: assets/.staged (to detect when asset sources change)
assets/.staged: viewer-artifacts $(ASSET_STAGING_INPUTS)
	@echo "Aggregating assets from all widgets..."
	@bash scripts/stage_assets.sh
	@touch $@

# Legacy target for compatibility
stage-js: assets/.staged

# Stage the supplied web runtime; never invoke a dependency's build.
web/dart_wellen: assets/.staged
	@test -f "$@/wellen_bridge.js" -a -f "$@/wellen_bridge_bg.wasm" || \
		{ echo "ERROR: Missing packaged Wellen web runtime in $@. Supply the built viewer artifacts before running DevTools." >&2; exit 1; }

# Build web version with Flutter - output: build/web/index.html (Flutter's main artifact)
build/web/index.html: web/dart_wellen pubspec.yaml $(DART_SOURCES)
	@echo "Building Flutter debugger web app..."
	@cd "$(WORKSPACE_ROOT)" && flutter pub get
	@flutter build web --release --target=lib/main_standalone.dart $(FLUTTER_WEB_BUILD_ARGS)
	@bash $(ROOT)/scripts/verify_elk_distribution.sh $(ROOT)/build/web/assets
	@echo "Copying widget artifacts into build/web..."
	@rm -rf $(ROOT)/build/web/dart_wellen
	@cp -r $(ROOT)/web/dart_wellen $(ROOT)/build/web/
	@echo "Web build ready at: build/web/"

# Legacy target for compatibility
web: build/web/index.html

# Force a fresh release build. FLUTTER_WEB_BUILD_ARGS can set deployment
# options such as a repository-scoped base href.
web-release:
	@rm -f build/web/index.html
	@$(MAKE) build/web/index.html

# Run web standalone version (development - no stamp, always runs)
web-run: web/dart_wellen
	@echo "Ensuring ports are free..."
	@bash $(ROOT)/scripts/free_ports.sh
	@echo "Running Flutter web standalone app..."
	@cd "$(WORKSPACE_ROOT)" && flutter pub get
	@flutter run -d web-server --web-port=9099 --web-hostname=127.0.0.1 lib/main_standalone.dart

# Run web standalone version in profile mode (faster startup, limited debugging)
web-run-profile: web/dart_wellen
	@echo "Ensuring ports are free..."
	@bash $(ROOT)/scripts/free_ports.sh
	@echo "Running Flutter web standalone app (profile mode)..."
	@cd "$(WORKSPACE_ROOT)" && flutter pub get
	@flutter run -d web-server --web-port=9099 --web-hostname=127.0.0.1 --profile lib/main_standalone.dart

# Build Linux standalone version - output: build/linux/release/rohd_devtools
build/linux/release: assets/.staged pubspec.yaml $(DART_SOURCES)
	@echo "Building Flutter Linux standalone app..."
	@cd "$(WORKSPACE_ROOT)" && flutter pub get
	@flutter build linux --target=lib/main_standalone.dart
	@bash $(ROOT)/scripts/verify_elk_distribution.sh $(ROOT)/build/linux/x64/release/bundle/data/flutter_assets

# Legacy target for compatibility
linux: build/linux/release

# Clean all build artifacts
clean: clean-linux clean-web clean-assets
	@echo "Cleaning Flutter build cache..."
	@flutter clean
	@echo "Removing generated doc/..."
	-rm -rf $(ROOT)/doc
	@echo "Clean complete"

# Deep-clean extension outputs and in-repository widgets only.
real-clean: clean
	@echo "Performing real-clean - removing local build outputs..."
	@if [ -d "$(LOCAL_WIDGETS_DIR)" ]; then \
		echo "Real-cleaning $(LOCAL_WIDGETS_DIR)..."; \
		(cd "$(LOCAL_WIDGETS_DIR)" && flutter clean); \
	elif [ -d "$(ROOT)/packages/rohd_devtools_widgets" ]; then \
		echo "Real-cleaning $(ROOT)/packages/rohd_devtools_widgets..."; \
		(cd "$(ROOT)/packages/rohd_devtools_widgets" && flutter clean); \
	else \
		echo "No local rohd_devtools_widgets package found; skipping."; \
	fi
	@echo "Real-cleaning rohd_extension/dart..."
	-@cd ../rohd_extension/dart && flutter clean
	@echo "Removing .dart_tool and pub cache artifacts..."
	-rm -rf $(ROOT)/.dart_tool
	-rm -rf $(ROOT)/.dart_plugins
	-rm -rf $(ROOT)/pubspec.lock
	@echo "Removing staged assets (preserving source assets/help/)..."
	-rm -rf $(ROOT)/assets/js
	-rm -f $(ROOT)/assets/schematic_layout_bridge.js
	-rm -f $(ROOT)/assets/rohd_schematic.json
	-rm -f $(ROOT)/assets/elk_layout_only.js
	-rm -f $(ROOT)/assets/.staged
	@echo "Real-clean complete - run 'flutter pub get' to restore dependencies"

# Clean Linux build artifacts
clean-linux:
	@echo "Cleaning Linux build artifacts..."
	-rm -rf $(ROOT)/build/linux
	-rm -rf $(ROOT)/build/native_assets
	-rm -rf $(ROOT)/linux/flutter/ephemeral

# Clean web build artifacts
clean-web:
	@echo "Cleaning web build artifacts..."
	-rm -rf $(ROOT)/build/web
	-rm -rf $(ROOT)/build/flutter_assets
	-rm -rf $(ROOT)/build/extension
	@echo "Removing stale web asset files from parent directory..."
	-rm -f $(ROOT)/web/schematic_layout_bridge.js
	-rm -rf $(ROOT)/web/assets/js

# Clean staged assets (copied from widgets)
clean-assets:
	@echo "Cleaning staged assets..."
	-rm -rf $(ROOT)/assets/js
	-rm -f $(ROOT)/assets/schematic_layout_bridge.js
	-rm -f $(ROOT)/assets/rohd_schematic.json
	-rm -f $(ROOT)/assets/.staged

# Help target
help:
	@echo "ROHD Debugger Makefile"
	@echo ""
	@echo "Core Targets:"
	@echo "  all        - Build Linux standalone (default)"
	@echo "  linux      - Build Linux debugger app"
	@echo "  web        - Build debugger web app"
	@echo "  web-release - Force a release web build"
	@echo "  web-run    - Run web app in development mode"
	@echo "  test       - Run tests (Dart + widget integration)"
	@echo "  test-all   - Run all tests including the FilterBank loopback workflow"
	@echo "  coverage   - Generate coverage for rohd_devtools_extension"
	@echo "  coverage-view - Serve rohd_devtools_extension coverage locally"
	@echo "  coverage-clean - Remove rohd_devtools_extension coverage output"
	@echo ""
	@echo "Extension Targets:"
	@echo "  extension  - Build VS Code extension"
	@echo "  install-local - Install to local VS Code"
	@echo "  install-remote - Install to remote VS Code Server"
	@echo ""
	@echo "Asset Targets:"
	@echo "  stage-js   - Stage assets from all widgets"
	@echo "  viewer-artifacts - Install/verify prebuilt dependency artifacts"
	@echo ""
	@echo "Cleanup:"
	@echo "  clean      - Clean all build artifacts"
	@echo "  real-clean - Deep clean local outputs (external packages untouched)"
	@echo "  force      - Force rebuild (clean + all)"
	@echo ""
	@echo "Architecture:"
	@echo "  This Makefile is widget-agnostic. Top-level coordinates:"
	@echo "  - Asset staging from all widgets via scripts/stage_assets.sh"
	@echo "  - Normal app builds consume prepared viewer artifacts"
	@echo "  - Missing dependency artifacts must be supplied upstream"
	@echo "  - No hardcoded Rust/WASM/implementation details"

# Force rebuild of everything
force: clean all

# Package the debugger extension with its dependency assets.
# Output: build/extension/web/index.html (final deployable artifact)
extension: build/extension/web/index.html

# Build VS Code extension - copies and stages all required artifacts
# Requires: WASM, Flutter web build, and widget assets
build/extension/web/index.html: build/web/index.html
	@echo "Building VS Code extension (web + widget assets)..."
	@cd "$(WORKSPACE_ROOT)" && flutter pub get
	@mkdir -p build/extension
	@echo "Staging extension assets..."
	@cp -r assets build/extension/
	@cp -r web build/extension/
	@if [ -d "$(ROOT)/build/web" ]; then cp -r build/web build/extension/web_assets; fi
	@bash $(ROOT)/scripts/verify_elk_distribution.sh $(ROOT)/build/extension/web_assets/assets
	@echo "Extension built at build/extension/"

# Install extension locally to user's VS Code installation
install-local: build/extension/web/index.html
	@echo "Installing extension to local VS Code..."
	@mkdir -p ~/.vscode/extensions
	@cp -r build/extension ~/.vscode/extensions/rohd-devtools-extension
	@echo "Extension installed to ~/.vscode/extensions/rohd-devtools-extension"

# Install extension remotely to VS Code Server on remote machine
install-remote: build/extension/web/index.html
	@echo "Installing extension to remote VS Code Server..."
	@mkdir -p ~/.vscode-server/extensions
	@cp -r build/extension ~/.vscode-server/extensions/rohd-devtools-extension
	@echo "Extension installed to ~/.vscode-server/extensions/rohd-devtools-extension"
