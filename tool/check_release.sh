#!/bin/bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# check_release.sh
# Check selected publication archives without uploading packages.
#
# Usage (from repo root):
#   tool/check_release.sh [--validate-only] [package ...]
#
# With no package names, check rohd, rohd_hierarchy, rohd_waveform,
# rohd_devtools_widgets, and rohd_source_navigator. Each selected package
# uses its existing pubspec.yaml version; manifests and changelogs are not edited.
# Dart is required for Dart packages; Flutter is required for widgets.
#
# Examples:
#   tool/check_release.sh
#   tool/check_release.sh rohd
#   tool/check_release.sh rohd_hierarchy rohd_waveform
#   tool/check_release.sh rohd_devtools_widgets
#   tool/check_release.sh rohd_source_navigator
#   tool/check_release.sh --validate-only
#
# --validate-only checks names, manifests, and SDK availability without invoking
# SDK commands. Normal checks hard-code pub publish --dry-run with stdin closed;
# there is no upload mode and no forwarding of arbitrary pub options.
# Results are summarized; any failure or nonzero warning makes this script fail.
# Dry runs may update dependency caches/lockfiles. Local overrides are preserved
# and do not prove hosted dependency readiness. No commits, tags, or pushes occur.
# SDK telemetry is suppressed for these checks and their child analyzers only.
#
# For ROHD, first run tool/prepare_release.sh rohd to install verified DevTools.
# See doc/releases.md for preparation, hosted validation, and manual publication.
#
# 2026 September 18
# Author: Max Korbel <max.korbel@intel.com>

set -euo pipefail

export DASH__SUPPRESS_ANALYTICS=true
export FLUTTER_SUPPRESS_ANALYTICS=true

usage() {
  echo "Usage: $0 [--validate-only] [package ...]"
  echo "Packages: rohd rohd_hierarchy rohd_waveform rohd_devtools_widgets rohd_source_navigator"
  echo "Defaults to all five packages, using each package's pubspec.yaml version."
  echo "Runs publication dry runs only; never uploads packages."
}

if [[ $# -eq 1 && "$1" == '--help' ]]; then
  usage
  exit 0
fi

validate_only=false
if [[ "${1:-}" == '--validate-only' ]]; then
  validate_only=true
  shift
fi
if [[ $# -eq 0 ]]; then
  set -- rohd rohd_hierarchy rohd_waveform rohd_devtools_widgets rohd_source_navigator
fi

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
packages=()
directories=()
sdks=()

for package in "$@"; do
  case "$package" in
    rohd)
      directory="$REPO_ROOT"
      sdk=dart
      ;;
    rohd_hierarchy|rohd_waveform|rohd_source_navigator)
      directory="$REPO_ROOT/packages/$package"
      sdk=dart
      ;;
    rohd_devtools_widgets)
      directory="$REPO_ROOT/packages/$package"
      sdk=flutter
      ;;
    *)
      echo "Unsupported package or option: $package" >&2
      usage >&2
      exit 2
      ;;
  esac
  if [[ ! -f "$directory/pubspec.yaml" ]]; then
    echo "Missing package manifest: $directory/pubspec.yaml" >&2
    exit 2
  fi
  if ! command -v "$sdk" >/dev/null; then
    echo "Required SDK command not found: $sdk" >&2
    exit 2
  fi
  packages+=("$package")
  directories+=("$directory")
  sdks+=("$sdk")
done

if [[ "$validate_only" == true ]]; then
  echo "Selection validated; no SDK commands were run: ${packages[*]}"
  exit 0
fi

echo "Dry runs only. Package versions and local overrides are left unchanged."
echo "Local overrides can hide hosted dependency problems; repeat without them in a disposable checkout before publishing."
results=()
failed=0
for index in "${!packages[@]}"; do
  package="${packages[$index]}"
  directory="${directories[$index]}"
  sdk="${sdks[$index]}"
  printf '\n=== %s ===\n' "$package"
  if [[ "$package" == rohd ]] &&
      [[ ! -f "$REPO_ROOT/extension/devtools/build/index.html" ||
         ! -f "$REPO_ROOT/extension/devtools/config.yaml" ]]; then
    echo "ROHD requires its prepared DevTools build. Run tool/prepare_release.sh rohd first." >&2
    results+=("$package: FAILED (missing DevTools payload)")
    failed=1
    continue
  fi
  echo "Directory: $directory"
  echo "Command: $sdk pub publish --dry-run"
  if (cd "$directory" && "$sdk" pub publish --dry-run </dev/null); then
    results+=("$package: PASSED")
  else
    status=$?
    results+=("$package: FAILED (exit $status; see output above)")
    failed=1
  fi
done

printf '\nPublication dry-run summary:\n'
printf '  %s\n' "${results[@]}"
echo "No packages were uploaded. Nonzero pub results, including warnings, require review."
exit "$failed"
