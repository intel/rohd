# Minimal build entrypoints for the upstream standalone extension package.

ROOT := $(shell pwd)

.PHONY: all linux clean-linux help

all: linux

linux:
	@flutter pub get
	@flutter build linux --target=lib/main_standalone.dart

clean-linux:
	-rm -rf $(ROOT)/build/linux
	-rm -rf $(ROOT)/linux/flutter/ephemeral

help:
	@echo "ROHD DevTools Extension"
	@echo ""
	@echo "Targets:"
	@echo "  all         - Build the Linux standalone app (default)"
	@echo "  linux       - Run flutter pub get and build Linux standalone"
	@echo "  clean-linux - Remove Linux build outputs"