# Minimal build entrypoints for the upstream standalone extension package.

ROOT := $(shell pwd)
FLUTTER_WEB_BUILD_ARGS ?=

.PHONY: all linux web web-release clean-linux clean-web help

all: linux

linux:
	@flutter pub get
	@flutter build linux --target=lib/main_standalone.dart

web:
	@flutter pub get
	@flutter build web --release --target=lib/main_standalone.dart $(FLUTTER_WEB_BUILD_ARGS)

web-release:
	@rm -f build/web/index.html
	@$(MAKE) web

clean-linux:
	-rm -rf $(ROOT)/build/linux
	-rm -rf $(ROOT)/linux/flutter/ephemeral

clean-web:
	-rm -rf $(ROOT)/build/web

help:
	@echo "ROHD DevTools Extension"
	@echo ""
	@echo "Targets:"
	@echo "  all         - Build the Linux standalone app (default)"
	@echo "  linux       - Run flutter pub get and build Linux standalone"
	@echo "  web         - Build the web standalone app"
	@echo "  web-release - Force a release web build"
	@echo "  clean-linux - Remove Linux build outputs"
	@echo "  clean-web   - Remove web build outputs"