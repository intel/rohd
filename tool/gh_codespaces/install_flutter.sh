#!/bin/bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# install_flutter.sh
# GitHub Codespaces setup: Install the Flutter SDK used by the Pub workspace.

set -euo pipefail

readonly flutter_version="${FLUTTER_VERSION:-3.47.2}"
readonly flutter_root="${FLUTTER_ROOT:-$HOME/flutter}"

if [[ ! -x "$flutter_root/bin/flutter" ]]; then
  archive="$(mktemp "${TMPDIR:-/tmp}/flutter.XXXXXX.tar.xz")"
  trap 'rm -f -- "$archive"' EXIT
  curl --fail --location --silent --show-error \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${flutter_version}-stable.tar.xz" \
    --output "$archive"
  tar -xJf "$archive" -C "$HOME"
fi

export FLUTTER_ROOT="$flutter_root"
export PATH="$flutter_root/bin:$PATH"
flutter config --no-analytics
flutter --version

if ! grep -Fqx "export PATH=\"$flutter_root/bin:\$PATH\"" "$HOME/.bashrc"; then
  printf 'export PATH="%s/bin:$PATH"\n' "$flutter_root" >>"$HOME/.bashrc"
fi
