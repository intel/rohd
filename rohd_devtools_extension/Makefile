# Makefile for ROHD DevTools Extension
# Restructured to leverage widget Makefiles (rohd-schematic-viewer, rohd-wave-viewer)
# Minimal redundancy: each widget manages its own build, assets copied at top level

ROOT := $(shell pwd)
STAMP_DIR := $(ROOT)/build/.stamp

# Widget list - each has its own Makefile
WIDGETS := rohd-schematic-viewer rohd-wave-viewer

# Source file patterns for dependency tracking
DART_SOURCES := $(shell find lib -name '*.dart' 2>/dev/null) $(shell for w in $(WIDGETS); do find $$w/lib -name '*.dart' 2>/dev/null; done)
WIDGET_SOURCES := $(shell for w in $(WIDGETS); do find $$w -name '*.dart' -o -name '*.js' -o -name '*.ts' 2>/dev/null; done)

.PHONY: all build-linux build-web clean clean-linux clean-web clean-stamps web-run web-run-profile help force real-clean extension install-local install-remote test dart-bindings widget-prepare $(addprefix widget-,$(WIDGETS))

all: linux

# Ensure all widget dependencies are ready (each widget manages its own bindings)
# This delegates to widget Makefiles which handle language-specific bindings.
dart-bindings:
	@for widget in $(WIDGETS); do \
		echo "Ensuring $$widget bindings..."; \
		cd $(ROOT)/$$widget && $(MAKE) dart-bindings 2>/dev/null || true; \
	done

# Run tests on Chrome (required because devtools_extensions uses dart:js_interop).
# Each test file gets its own `flutter test` invocation because the DDC
# incremental compiler hangs when loading a second test file into the same
# Chrome tab.  Lightweight cubit tests + widget tests go here (~1 min cached).
# The filter_bank integration test imports the full ROHD simulation stack
# which takes several minutes to DDC-compile — run via `make test-integration`.
test: assets/.staged dart-bindings
	@flutter test --platform chrome test/modules/cubit/cubit_test.dart
	@flutter test --platform chrome test/modules/tree_structure/tree_structure_page_test.dart
	@flutter test --platform chrome test/modules/tree_structure/model_tree_card_test.dart

# Full integration test using the real FilterBank ROHD example in loopback mode.
# First run after `flutter clean` takes ~5 min (DDC compiles ROHD → JS); cached runs ~30s.
test-integration: assets/.staged dart-bindings
	@flutter test --platform chrome test/integration/filter_bank_integration_test.dart

# Run everything.
test-all: test test-integration

# Stage assets from all widgets - copies their assets to canonical assets/ location
# Each widget contributes its own assets; top-level script merges them.
# Flutter's pubspec.yaml declares assets/ and automatically bundles into:
#  - build/web/assets/ (for web builds)
#  - build/linux/assets/ (for Linux native builds)
# Output marker: assets/.staged (to detect when asset sources change)
assets/.staged: $(WIDGET_SOURCES)
	@echo "Aggregating assets from all widgets..."
	@bash scripts/stage_assets.sh
	@touch $@

# Legacy target for compatibility
stage-js: assets/.staged

# Prepare web artifacts (delegated to widgets that provide them)
# Each widget that supports web builds handles its own artifacts.
web/pkg: assets/.staged dart-bindings
	@echo "Preparing web artifacts from widgets..."
	@for widget in $(WIDGETS); do \
		if [ -f "$$widget/Makefile" ] && grep -q '^wasm:' "$$widget/Makefile" 2>/dev/null; then \
			echo "Building web artifacts from $$widget..."; \
			cd $(ROOT)/$$widget && $(MAKE) wasm; \
		fi; \
	done

# Build web version with Flutter - output: build/web/index.html (Flutter's main artifact)
build/web/index.html: web/pkg pubspec.yaml $(DART_SOURCES)
	@echo "Building Flutter web app with all widgets..."
	@bash $(ROOT)/scripts/ensure_dart_bindings.sh
	@flutter pub get
	@flutter build web --release --target=lib/main_standalone.dart
	@echo "Copying widget artifacts into build/web..."
	@rm -rf $(ROOT)/build/web/pkg
	@for widget in $(WIDGETS); do \
		if [ -d "$(ROOT)/$$widget/web/pkg" ]; then \
			cp -r $(ROOT)/$$widget/web/pkg $(ROOT)/build/web/; \
			break; \
		fi; \
	done
	@echo "Web build ready at: build/web/"

# Legacy target for compatibility
web: build/web/index.html

# Run web standalone version (development - no stamp, always runs)
web-run: web/pkg
	@echo "Ensuring ports are free..."
	@bash $(ROOT)/scripts/free_ports.sh
	@echo "Running Flutter web standalone app..."
	@bash $(ROOT)/scripts/ensure_dart_bindings.sh
	@flutter pub get
	@flutter run -d web-server --web-port=9099 --web-hostname=0.0.0.0 lib/main_standalone.dart

# Run web standalone version in profile mode (faster startup, limited debugging)
web-run-profile: web/pkg
	@echo "Ensuring ports are free..."
	@bash $(ROOT)/scripts/free_ports.sh
	@echo "Running Flutter web standalone app (profile mode)..."
	@bash $(ROOT)/scripts/ensure_dart_bindings.sh
	@flutter pub get
	@flutter run -d web-server --web-port=9099 --web-hostname=0.0.0.0 --profile lib/main_standalone.dart

# Prepare all widgets (compilation of native/wasm code, asset staging, bindings)
# Each widget handles its own build requirements - top-level never knows implementation details
widget-prepare: dart-bindings
	@for widget in $(WIDGETS); do \
		if [ -f "$$widget/Makefile" ] && grep -q '^prepare:' "$$widget/Makefile" 2>/dev/null; then \
			echo "Preparing $$widget..."; \
			cd $(ROOT)/$$widget && $(MAKE) prepare; \
		fi; \
	done

# Build Linux standalone version - output: build/linux/release/rohd_devtools
build/linux/release: widget-prepare assets/.staged pubspec.yaml $(DART_SOURCES)
	@echo "Building Flutter Linux standalone app..."
	@bash $(ROOT)/scripts/ensure_dart_bindings.sh
	@flutter pub get
	@flutter build linux --target=lib/main_standalone.dart

# Legacy target for compatibility
linux: build/linux/release

# Clean all build artifacts
clean: clean-linux clean-web clean-assets
	@echo "Cleaning Flutter build cache..."
	@flutter clean
	@echo "Removing generated doc/..."
	-rm -rf $(ROOT)/doc
	@echo "Clean complete"

# Real-clean - deep clean including dependency packages and all widget submodules
real-clean: clean
	@echo "Performing real-clean - removing all build outputs and packages..."
	@echo "Real-cleaning packages/rohd_devtools_widgets..."
	@cd packages/rohd_devtools_widgets && flutter clean
	@for widget in $(WIDGETS); do \
		echo "Real-cleaning $$widget..."; \
		cd $(ROOT)/$$widget && $(MAKE) real-clean; \
	done
	@echo "Real-cleaning rohd_extension/dart..."
	-@cd ../rohd_extension/dart && flutter clean
	@echo "Removing generated flutter_rust_bridge artifacts..."
	-find $(ROOT)/packages -name "flutter_rust_bridge.generated*" -delete
	@for widget in $(WIDGETS); do \
		find $(ROOT)/$$widget/packages -name "flutter_rust_bridge.generated*" -delete 2>/dev/null || true; \
	done
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
	@echo "  linux      - Build Linux standalone app (all widgets)"
	@echo "  web        - Build web app (all widgets)"
	@echo "  web-run    - Run web app in development mode"
	@echo "  test       - Run tests (Dart + widget integration)"
	@echo "  test-all   - Run all tests including integration tests"
	@echo ""
	@echo "Extension Targets:"
	@echo "  extension  - Build VS Code extension"
	@echo "  install-local - Install to local VS Code"
	@echo "  install-remote - Install to remote VS Code Server"
	@echo ""
	@echo "Asset Targets:"
	@echo "  stage-js   - Stage assets from all widgets"
	@echo "  dart-bindings - Ensure all widget bindings are ready"
	@echo ""
	@echo "Cleanup:"
	@echo "  clean      - Clean all build artifacts"
	@echo "  real-clean - Deep clean: all builds, packages, widget artifacts"
	@echo "  force      - Force rebuild (clean + all)"
	@echo ""
	@echo "Architecture:"
	@echo "  This Makefile is widget-agnostic. Top-level coordinates:"
	@echo "  - Asset staging from all widgets via scripts/stage_assets.sh"
	@echo "  - Bindings preparation by delegating to each widget"
	@echo "  - Web/native builds by discovering widget capabilities"
	@echo "  - Each widget manages its own implementation"
	@echo "  - No hardcoded Rust/WASM/implementation details"

# Force rebuild of everything
force: clean all

# Build the VSCode extension with all dependencies (schematic viewer + wave viewer)
# Output: build/extension/web/index.html (final deployable artifact)
extension: build/extension/web/index.html

# Build VS Code extension - copies and stages all required artifacts
# Requires: WASM, Flutter web build, and widget assets
build/extension/web/index.html: build/web/index.html
	@echo "Building VS Code extension (web + widget assets)..."
	@bash $(ROOT)/scripts/ensure_dart_bindings.sh
	@flutter pub get
	@mkdir -p build/extension
	@echo "Staging extension assets..."
	@cp -r assets build/extension/
	@cp -r web build/extension/
	@if [ -d "$(ROOT)/build/web" ]; then cp -r build/web build/extension/web_assets; fi
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
