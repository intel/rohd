#!/bin/bash

# Copyright (C) 2025 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# pana_source.sh
# GitHub Actions step: execute pana analysis on project source.
# With <package-directory> <dart|flutter>, check an isolated package instead.
#
# 2025 September 26
# Author: Desmond A. Kirkpatrick

set -euo pipefail

export PATH="$PATH:${PUB_CACHE:-$HOME/.pub-cache}/bin"

if [[ $# -eq 0 ]]; then
  exec pana --exit-code-threshold 0 .
fi
if [[ $# -ne 2 || ! -f "$1/pubspec.yaml" ||
      ( "$2" != dart && "$2" != flutter ) ]]; then
  echo "Usage: $0 [<package-directory> <dart|flutter>]" >&2
  exit 2
fi
if ! command -v pana > /dev/null; then
  echo "Pana is required; run tool/gh_actions/install_pana.sh first." >&2
  exit 2
fi

package_dir="$(cd "$1" && pwd)"
sdk="$2"
analyze_arguments=(analyze --fatal-infos)
pana_arguments=()
if [[ "$sdk" == flutter ]]; then
  flutter_root="${FLUTTER_ROOT:-}"
  if [[ -z "$flutter_root" ]]; then
    flutter_executable="$(command -v flutter)"
    flutter_root="$(dirname "$(dirname "$(readlink -f "$flutter_executable")")")"
  fi
  pana_arguments+=(--flutter-sdk "$flutter_root")
  analyze_arguments+=(--no-pub)
fi

temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/rohd-pana.XXXXXXXX")"
trap 'rm -rf "$temp_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir "$temp_dir/package"
# Checkout lint includes are repository-relative; compatibility analysis below
# checks the library, while normal CI retains the full repository lint policy.
tar -C "$package_dir" \
  --exclude=.git --exclude=.dart_tool --exclude=.packages \
  --exclude=build --exclude=coverage --exclude=analysis_options.yaml \
  --exclude=pubspec.lock --exclude=pubspec_overrides.yaml \
  --exclude=.flutter-plugins --exclude=.flutter-plugins-dependencies \
  -cf - . | tar -C "$temp_dir/package" -xf -
cd "$temp_dir/package"
if grep -Eq '^[[:space:]]*dependency_overrides[[:space:]]*:' pubspec.yaml; then
  echo "Move inline dependency overrides to pubspec_overrides.yaml before hosted checks." >&2
  exit 2
fi

echo "=== ${package_dir##*/}: hosted dependency compatibility ==="
"$sdk" pub get
"$sdk" "${analyze_arguments[@]}" lib
"$sdk" pub downgrade
"$sdk" "${analyze_arguments[@]}" lib

echo "=== ${package_dir##*/}: Pana report (package scores are advisory) ==="
PANA_ANALYSIS_INCLUDES=0 pana "${pana_arguments[@]}" .
