#!/bin/bash

# Copyright (C) 2024-2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# setup_systemc_pch.sh
# GitHub Actions step: Pre-build SystemC precompiled header and Makefile.
#
# Run this after install_systemc.sh and before tests to avoid race
# conditions when multiple test isolates run in parallel.
#
# 2026 May
# Author: Desmond Kirkpatrick

set -euo pipefail

SC_HOME="${SYSTEMC_INCLUDE:-/opt/systemc/include}"
SC_LIB="${SYSTEMC_LIB:-/opt/systemc/lib}"

if [ ! -d "$SC_HOME" ]; then
  echo "SystemC not found at $SC_HOME — skipping PCH setup."
  exit 0
fi

# Detect C++ standard from the installed library
CXX_STD="c++17"
if command -v nm &>/dev/null && [ -f "$SC_LIB/libsystemc.so" ]; then
  if nm -D "$SC_LIB/libsystemc.so" 2>/dev/null | grep -q 'cxx202002L'; then
    CXX_STD="c++20"
  fi
fi

echo "Setting up SystemC PCH ($CXX_STD) ..."

# Build precompiled header
PCH_DIR="tmp_test/pch"
mkdir -p "$PCH_DIR"
cp "$SC_HOME/systemc.h" "$PCH_DIR/systemc.h"
g++ -std="$CXX_STD" -I"$SC_HOME" -x c++-header \
    -o "$PCH_DIR/systemc.h.gch" "$SC_HOME/systemc.h"

echo "PCH built: $PCH_DIR/systemc.h.gch"

# Pre-create the shared Makefile
MAKEFILE="tmp_test/Makefile_sc"
cat > "$MAKEFILE" <<'EOF'
CXX = g++
CXXFLAGS = -std=__CXX_STD__ -pipe -I__PCH_DIR__ -I__SC_HOME__
LDFLAGS = -L__SC_LIB__ -lsystemc

all: $(TARGET)

$(TARGET): $(SRC)
	$(CXX) $(CXXFLAGS) -o $(TARGET) $(SRC) $(LDFLAGS)

.PHONY: all
EOF

# Substitute paths into the Makefile
sed -i "s|__CXX_STD__|$CXX_STD|g" "$MAKEFILE"
sed -i "s|__PCH_DIR__|$PCH_DIR|g" "$MAKEFILE"
sed -i "s|__SC_HOME__|$SC_HOME|g" "$MAKEFILE"
sed -i "s|__SC_LIB__|$SC_LIB|g" "$MAKEFILE"

echo "Makefile created: $MAKEFILE"
