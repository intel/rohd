#!/bin/bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# check_release_test.sh
# Test package selection, SDK routing, and dry-run failure reporting.
# Uses temporary files and fake SDK executables on a restricted PATH;
# no real Dart or Flutter publication commands can run.
#
# Usage (from repo root):
#   bash tool/test/check_release_test.sh
#
# 2026 September 18
# Author: Max Korbel <max.korbel@intel.com>

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p "$FIXTURE/repo/tool" "$FIXTURE/bin" "$FIXTURE/repo/extension/devtools/build"
cp "$REPO_ROOT/tool/check_release.sh" "$REPO_ROOT/tool/prepare_release.sh" "$FIXTURE/repo/tool/"
for package in rohd_hierarchy rohd_waveform rohd_devtools_widgets; do
  mkdir -p "$FIXTURE/repo/packages/$package"
  touch "$FIXTURE/repo/packages/$package/pubspec.yaml"
done
touch "$FIXTURE/repo/pubspec.yaml" "$FIXTURE/repo/extension/devtools/build/index.html"
touch "$FIXTURE/repo/extension/devtools/config.yaml"

printf '%s\n' \
  '#!/bin/bash' \
  'printf "%s|%s|%s\n" "${0##*/}" "$PWD" "$*" >> "$SDK_LOG"' \
  '[[ "$#" -eq 3 && "$1" == pub && "$2" == publish && "$3" == --dry-run ]] || exit 99' \
  '[[ "${DASH__SUPPRESS_ANALYTICS:-}" == true ]] || exit 98' \
  '[[ "${FLUTTER_SUPPRESS_ANALYTICS:-}" == true ]] || exit 97' \
  'if [[ "${FAIL_PACKAGE:-}" == "${PWD##*/}" ]]; then exit 65; fi' \
  'exit 0' > "$FIXTURE/bin/sdk"
chmod +x "$FIXTURE/bin/sdk"
ln -s sdk "$FIXTURE/bin/dart"
ln -s sdk "$FIXTURE/bin/flutter"
ln -s /bin/bash "$FIXTURE/bin/bash"
ln -s "$(command -v dirname)" "$FIXTURE/bin/dirname"

export SDK_LOG="$FIXTURE/sdk.log"
readonly HELPER="$FIXTURE/repo/tool/check_release.sh"
passed=0

run_case() {
  local expected="$1"
  local script="$2"
  shift 2
  : > "$SDK_LOG"
  local status=0
  PATH="$FIXTURE/bin" /bin/bash "$script" "$@" > "$FIXTURE/output" 2>&1 || status=$?
  if [[ "$status" -ne "$expected" ]]; then
    cat "$FIXTURE/output"
    echo "Expected exit $expected, got $status for: $*" >&2
    exit 1
  fi
  passed=$((passed + 1))
}

run_case 0 "$HELPER" --help
[[ ! -s "$SDK_LOG" ]]
run_case 0 "$HELPER"
[[ "$(wc -l < "$SDK_LOG")" -eq 4 ]]
DASH__SUPPRESS_ANALYTICS=false FLUTTER_SUPPRESS_ANALYTICS=false run_case 0 "$HELPER" rohd_devtools_widgets
run_case 0 "$HELPER" --validate-only
[[ ! -s "$SDK_LOG" ]]
for invalid in --force --dry-run ../rohd rohd_source_navigator rohd_devtools_extension; do
  run_case 2 "$HELPER" rohd_hierarchy "$invalid"
  [[ ! -s "$SDK_LOG" ]]
done
run_case 0 "$HELPER" --validate-only rohd rohd_devtools_widgets
[[ ! -s "$SDK_LOG" ]]

cd "$FIXTURE"
run_case 0 "$HELPER" rohd rohd_hierarchy rohd_waveform rohd_devtools_widgets
[[ "$(wc -l < "$SDK_LOG")" -eq 4 ]]
grep -Fx "dart|$FIXTURE/repo|pub publish --dry-run" "$SDK_LOG"
grep -Fx "dart|$FIXTURE/repo/packages/rohd_hierarchy|pub publish --dry-run" "$SDK_LOG"
grep -Fx "dart|$FIXTURE/repo/packages/rohd_waveform|pub publish --dry-run" "$SDK_LOG"
grep -Fx "flutter|$FIXTURE/repo/packages/rohd_devtools_widgets|pub publish --dry-run" "$SDK_LOG"

export FAIL_PACKAGE=rohd_hierarchy
run_case 1 "$HELPER" rohd_hierarchy rohd_waveform
[[ "$(wc -l < "$SDK_LOG")" -eq 2 ]]
grep -F 'rohd_hierarchy: FAILED (exit 65;' "$FIXTURE/output"
grep -F 'rohd_waveform: PASSED' "$FIXTURE/output"
unset FAIL_PACKAGE

rm "$FIXTURE/repo/extension/devtools/build/index.html"
run_case 1 "$HELPER" rohd rohd_hierarchy
[[ "$(wc -l < "$SDK_LOG")" -eq 1 ]]
grep -F 'rohd: FAILED (missing DevTools payload)' "$FIXTURE/output"
run_case 0 "$HELPER" --validate-only rohd
[[ ! -s "$SDK_LOG" ]]

touch "$FIXTURE/repo/extension/devtools/build/index.html"
rm "$FIXTURE/repo/extension/devtools/config.yaml"
run_case 1 "$HELPER" rohd
[[ ! -s "$SDK_LOG" ]]

rm "$FIXTURE/repo/packages/rohd_waveform/pubspec.yaml"
run_case 2 "$HELPER" rohd_hierarchy rohd_waveform
[[ ! -s "$SDK_LOG" ]]
rm "$FIXTURE/bin/flutter"
run_case 2 "$HELPER" rohd_hierarchy rohd_devtools_widgets
[[ ! -s "$SDK_LOG" ]]

run_case 2 "$FIXTURE/repo/tool/prepare_release.sh" rohd --force
[[ ! -s "$SDK_LOG" ]]
run_case 2 "$FIXTURE/repo/tool/prepare_release.sh"
[[ ! -s "$SDK_LOG" ]]
run_case 2 "$FIXTURE/repo/tool/prepare_release.sh" 0.6.11-rc.1
[[ ! -s "$SDK_LOG" ]]
run_case 2 "$FIXTURE/repo/tool/prepare_release.sh" rohd_devtools_widgets
[[ ! -s "$SDK_LOG" ]]

echo "$passed checks passed using only fake SDK executables."
