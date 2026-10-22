#!/bin/bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# Run the shared Pana checks for all publishable ROHD packages, or a selection.
#
# 2026 October
# Author: Desmond Kirkpatrick <desmond.dak@intel.com>

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
readonly ALL_PACKAGES=(
  rohd
  rohd_hierarchy
  rohd_waveform
  rohd_devtools_widgets
  rohd_source_navigator
)

if [[ $# -eq 1 && "$1" == --help ]]; then
  echo "Usage: tool/run_pana.sh [package ...]"
  echo "Runs hosted dependency compatibility checks and Pana score gates."
  echo "Defaults to all five publishable ROHD packages."
  exit 0
fi

packages=("$@")
if [[ ${#packages[@]} -eq 0 ]]; then
  packages=("${ALL_PACKAGES[@]}")
fi

failure_status=0
for package in "${packages[@]}"; do
  case "$package" in
    rohd|rohd_hierarchy|rohd_waveform|rohd_devtools_widgets|\
      rohd_source_navigator) ;;
    *)
      echo "Unsupported package '$package'." >&2
      echo "Supported packages: ${ALL_PACKAGES[*]}." >&2
      exit 2
      ;;
  esac
done

export PATH="$PATH:${PUB_CACHE:-$HOME/.pub-cache}/bin"
if ! command -v pana > /dev/null; then
  echo "Pana is required; run tool/gh_actions/install_pana.sh first." >&2
  exit 2
fi

for package in "${packages[@]}"; do
  sdk=dart
  package_dir="$REPO_ROOT"
  if [[ "$package" != rohd ]]; then
    package_dir="$REPO_ROOT/packages/$package"
  fi
  if [[ "$package" == rohd_devtools_widgets ]]; then
    sdk=flutter
  fi
  echo "=== Running Pana for $package ==="
  if bash "$SCRIPT_DIR/gh_actions/pana_source.sh" "$package_dir" "$sdk"; then
    continue
  else
    package_status=$?
    echo "Pana failed for $package (exit $package_status)." >&2
    failure_status="$package_status"
  fi
done

exit "$failure_status"
