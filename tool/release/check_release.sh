#!/bin/bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# check_release.sh
# Check selected publication archives without uploading packages.
#
# Usage (from repo root):
#   tool/release/check_release.sh [--validate-only] [package ...]
#
# With no package names, check rohd, rohd_hierarchy, rohd_waveform,
# rohd_devtools_widgets, rohd_source_navigator, and rohd_live_debugger. Each selected package
# uses its existing pubspec.yaml version; manifests and changelogs are not edited.
# Dart is required for Dart packages; Flutter is required for widgets.
#
# Examples:
#   tool/release/check_release.sh
#   tool/release/check_release.sh rohd
#   tool/release/check_release.sh rohd_hierarchy rohd_waveform
#   tool/release/check_release.sh rohd_devtools_widgets
#   tool/release/check_release.sh rohd_source_navigator
#   tool/release/check_release.sh --validate-only
#
# --validate-only checks names, manifests, and SDK availability without invoking
# SDK commands. Normal checks hard-code pub publish --dry-run with stdin closed;
# there is no upload mode and no forwarding of arbitrary pub options.
# Results are summarized; any failure or nonzero warning makes this script fail.
# Nested-package checks temporarily remove the root /packages/ ignore rule.
# Do not publish or edit .pubignore concurrently in this checkout.
# Dry runs may update dependency caches/lockfiles. Local overrides are preserved
# and do not prove hosted dependency readiness. No commits, tags, or pushes occur.
# SDK telemetry is suppressed for these checks and their child analyzers only.
#
# For rohd_live_debugger, first run its preparation to install verified DevTools.
# See doc/releases.md for preparation, hosted validation, and manual publication.
#
# 2026 September 18
# Author: Max Korbel <max.korbel@intel.com>

set -euo pipefail

export DASH__SUPPRESS_ANALYTICS=true
export FLUTTER_SUPPRESS_ANALYTICS=true

usage() {
  echo "Usage: $0 [--validate-only] [package ...]"
  echo "Packages: rohd rohd_hierarchy rohd_waveform rohd_devtools_widgets rohd_source_navigator rohd_live_debugger"
  echo "Defaults to all six packages, using each package's pubspec.yaml version."
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
  set -- rohd rohd_hierarchy rohd_waveform rohd_devtools_widgets rohd_source_navigator rohd_live_debugger
fi

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
packages=()
directories=()
sdks=()

for package in "$@"; do
  case "$package" in
    rohd)
      directory="$REPO_ROOT"
      sdk=dart
      ;;
    rohd_hierarchy|rohd_waveform|rohd_source_navigator|rohd_live_debugger)
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
readonly IGNORE_FILE="$REPO_ROOT/.pubignore"
readonly LOCK_DIR="$REPO_ROOT/.pubignore-release.lock"
if [[ ! -f "$IGNORE_FILE" || -L "$IGNORE_FILE" ]] ||
    [[ "$(grep -cFx '/packages/' "$IGNORE_FILE" || true)" != 1 ]]; then
  echo "Expected exactly one /packages/ rule in the regular root .pubignore file." >&2
  exit 2
fi
if ! mkdir "$LOCK_DIR"; then
  echo "Release check lock exists: $LOCK_DIR. Another check may be running, or recovery may be required." >&2
  exit 2
fi

ignore_active=false
restore_ignore() {
  if [[ "$ignore_active" == true ]]; then
    if ! cmp -s "$IGNORE_FILE" "$LOCK_DIR/without-packages"; then
      echo "Root .pubignore changed during the check; not overwriting it." >&2
      echo "Restore the /packages/ rule manually; the original is saved at $LOCK_DIR/original." >&2
      return 1
    fi
    cp -p "$LOCK_DIR/original" "$LOCK_DIR/replacement" || return 1
    mv "$LOCK_DIR/replacement" "$IGNORE_FILE" || return 1
    ignore_active=false
  fi
}
cleanup() {
  if ! restore_ignore; then
    echo "Release check could not restore .pubignore; retain $LOCK_DIR for recovery." >&2
    return 1
  fi
  rm -f "$LOCK_DIR/original" "$LOCK_DIR/without-packages" "$LOCK_DIR/replacement"
  rmdir "$LOCK_DIR"
}
trap 'cleanup || exit 1' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

cp -p "$IGNORE_FILE" "$LOCK_DIR/original"
cp -p "$IGNORE_FILE" "$LOCK_DIR/without-packages"
sed '/^\/packages\/$/d' "$IGNORE_FILE" > "$LOCK_DIR/without-packages"

results=()
failed=0
for index in "${!packages[@]}"; do
  package="${packages[$index]}"
  directory="${directories[$index]}"
  sdk="${sdks[$index]}"
  printf '\n=== %s ===\n' "$package"
  if [[ "$package" == rohd_live_debugger ]] &&
      [[ ! -f "$directory/extension/devtools/build/index.html" ||
         ! -f "$directory/extension/devtools/config.yaml" ]]; then
    echo "rohd_live_debugger requires its prepared DevTools build. Run tool/release/prepare_release.sh rohd_live_debugger first." >&2
    results+=("$package: FAILED (missing DevTools payload)")
    failed=1
    continue
  fi
  if ! cmp -s "$IGNORE_FILE" "$LOCK_DIR/original"; then
    echo "Root .pubignore changed during the check; not overwriting it." >&2
    failed=1
    break
  fi
  if [[ "$package" != rohd ]]; then
    cp -p "$LOCK_DIR/without-packages" "$LOCK_DIR/replacement"
    ignore_active=true
    mv "$LOCK_DIR/replacement" "$IGNORE_FILE"
  fi
  echo "Directory: $directory"
  echo "Command: $sdk pub publish --dry-run"
  status=0
  (cd "$directory" && "$sdk" pub publish --dry-run </dev/null) || status=$?
  if ! restore_ignore; then
    failed=1
    break
  fi
  if [[ "$status" -eq 0 ]]; then
    results+=("$package: PASSED")
  else
    results+=("$package: FAILED (exit $status; see output above)")
    failed=1
  fi
done

printf '\nPublication dry-run summary:\n'
printf '  %s\n' "${results[@]}"
echo "No packages were uploaded. Nonzero pub results, including warnings, require review."
exit "$failed"
