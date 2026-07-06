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
