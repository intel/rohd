#!/bin/bash

# Copyright (C) 2024-2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# install_systemc.sh
# GitHub Actions step: Install Accellera SystemC library.
#
# Downloads, builds, and installs SystemC to /opt/systemc.
# Uses a cache-friendly layout so the install directory can be
# cached across CI runs.
#
# 2026 May
# Author: Desmond Kirkpatrick

set -euo pipefail

SYSTEMC_VERSION="${SYSTEMC_VERSION:-3.0.2}"
INSTALL_PREFIX="${SYSTEMC_INSTALL_PREFIX:-/opt/systemc}"

if [ "$(id -u)" -eq 0 ]; then
  SUDO=()
else
  SUDO=(sudo)
fi

# Skip if already installed (e.g. from cache)
if [ -f "$INSTALL_PREFIX/lib/libsystemc.so" ]; then
  echo "SystemC already installed at $INSTALL_PREFIX — skipping build."
  exit 0
fi

echo "Installing Accellera SystemC $SYSTEMC_VERSION to $INSTALL_PREFIX ..."

# Install build dependencies
"${SUDO[@]}" apt-get update -qq
"${SUDO[@]}" apt-get install --yes --no-install-recommends cmake g++ make

# Download source
TARBALL="systemc-$SYSTEMC_VERSION.tar.gz"
DOWNLOAD_URL="https://github.com/accellera-official/systemc/archive/refs/tags/$SYSTEMC_VERSION.tar.gz"

cd /tmp
curl -fsSL -o "$TARBALL" "$DOWNLOAD_URL"
tar xzf "$TARBALL"
cd "systemc-$SYSTEMC_VERSION"

# Build with CMake
mkdir -p build && cd build
cmake .. \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CXX_STANDARD=17 \
  -DBUILD_SHARED_LIBS=ON \
  -DENABLE_EXAMPLES=OFF \
  -DENABLE_REGRESSION=OFF \
  -DDISABLE_COPYRIGHT_MESSAGE=ON

make -j"$(nproc)"
"${SUDO[@]}" make install

echo "SystemC $SYSTEMC_VERSION installed to $INSTALL_PREFIX"
