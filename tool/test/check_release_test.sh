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

mkdir -p "$FIXTURE/repo/tool/release" "$FIXTURE/bin" "$FIXTURE/repo/packages/rohd_live_debugger/extension/devtools/build"
cp "$REPO_ROOT/tool/release/check_release.sh" \
  "$REPO_ROOT/tool/release/prepare_release.sh" \
  "$FIXTURE/repo/tool/release/"
for package in rohd_hierarchy rohd_waveform rohd_devtools_widgets rohd_source_navigator rohd_live_debugger; do
  mkdir -p "$FIXTURE/repo/packages/$package"
  touch "$FIXTURE/repo/packages/$package/pubspec.yaml"
done
touch "$FIXTURE/repo/pubspec.yaml" "$FIXTURE/repo/packages/rohd_live_debugger/extension/devtools/build/index.html"
touch "$FIXTURE/repo/packages/rohd_live_debugger/extension/devtools/config.yaml"
cp "$REPO_ROOT/.pubignore" "$FIXTURE/repo/.pubignore"
cp "$FIXTURE/repo/.pubignore" "$FIXTURE/original-pubignore"
printf 'name: rohd_live_debugger\nresolution: workspace\n' > \
  "$FIXTURE/repo/packages/rohd_live_debugger/pubspec.yaml"

printf '%s\n' \
  '#!/bin/bash' \
  'if [[ "$PWD" == "$TEST_REPO" ]]; then' \
  '  grep -Fxq /packages/ "$TEST_REPO/.pubignore" || exit 94' \
  'else' \
  '  ! grep -Fxq /packages/ "$TEST_REPO/.pubignore" || exit 93' \
  'fi' \
  'if [[ "${PWD##*/}" == rohd_live_debugger ]]; then' \
  '  [[ "$PWD" == "$TEST_DEBUGGER_DIR" && -f extension/devtools/build/index.html && -f extension/devtools/config.yaml ]] || exit 96' \
  '  grep -q "^resolution: workspace$" pubspec.yaml || exit 95' \
  'fi' \
  'printf "%s|%s|%s\n" "${0##*/}" "$PWD" "$*" >> "$SDK_LOG"' \
  '[[ "$#" -eq 3 && "$1" == pub && "$2" == publish && "$3" == --dry-run ]] || exit 99' \
  '[[ "${DASH__SUPPRESS_ANALYTICS:-}" == true ]] || exit 98' \
  '[[ "${FLUTTER_SUPPRESS_ANALYTICS:-}" == true ]] || exit 97' \
  'if [[ "${MUTATE_IGNORE:-}" == 1 ]]; then printf "# concurrent edit\n" >> "$TEST_REPO/.pubignore"; fi' \
  'if [[ "${SIGNAL_PARENT:-}" == 1 ]]; then' \
  '  while [[ ! -s "$SIGNAL_PID_FILE" ]]; do sleep 0.01; done' \
  '  read -r check_pid < "$SIGNAL_PID_FILE"' \
  '  kill -TERM "$check_pid"' \
  'fi' \
  'if [[ "${FAIL_PACKAGE:-}" == "${PWD##*/}" ]]; then exit 65; fi' \
  'exit 0' > "$FIXTURE/bin/sdk"
chmod +x "$FIXTURE/bin/sdk"
ln -s sdk "$FIXTURE/bin/dart"
ln -s sdk "$FIXTURE/bin/flutter"
ln -s /bin/bash "$FIXTURE/bin/bash"
for executable in awk cmp cp dirname grep mkdir mktemp mv rm rmdir sed sleep tar; do
  ln -s "$(command -v "$executable")" "$FIXTURE/bin/$executable"
done

export SDK_LOG="$FIXTURE/sdk.log"
export TEST_REPO="$FIXTURE/repo"
export TEST_DEBUGGER_DIR="$FIXTURE/repo/packages/rohd_live_debugger"
readonly HELPER="$FIXTURE/repo/tool/release/check_release.sh"
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
  cmp "$FIXTURE/original-pubignore" "$FIXTURE/repo/.pubignore"
  [[ ! -e "$FIXTURE/repo/.pubignore-release.lock" ]]
  passed=$((passed + 1))
}

run_case 0 "$HELPER" --help
[[ ! -s "$SDK_LOG" ]]
run_case 0 "$HELPER"
[[ "$(wc -l < "$SDK_LOG")" -eq 6 ]]
grep -Fx "dart|$FIXTURE/repo/packages/rohd_source_navigator|pub publish --dry-run" "$SDK_LOG"
DASH__SUPPRESS_ANALYTICS=false FLUTTER_SUPPRESS_ANALYTICS=false run_case 0 "$HELPER" rohd_devtools_widgets
run_case 0 "$HELPER" --validate-only
[[ ! -s "$SDK_LOG" ]]
for invalid in --force --dry-run ../rohd rohd_devtools_extension; do
  run_case 2 "$HELPER" rohd_hierarchy "$invalid"
  [[ ! -s "$SDK_LOG" ]]
done
run_case 0 "$HELPER" --validate-only rohd rohd_devtools_widgets rohd_source_navigator
[[ ! -s "$SDK_LOG" ]]

cd "$FIXTURE"
run_case 0 "$HELPER" rohd rohd_hierarchy rohd_waveform rohd_devtools_widgets rohd_source_navigator rohd_live_debugger
[[ "$(wc -l < "$SDK_LOG")" -eq 6 ]]
grep -Fx "dart|$FIXTURE/repo|pub publish --dry-run" "$SDK_LOG"
grep -Fx "dart|$FIXTURE/repo/packages/rohd_hierarchy|pub publish --dry-run" "$SDK_LOG"
grep -Fx "dart|$FIXTURE/repo/packages/rohd_waveform|pub publish --dry-run" "$SDK_LOG"
grep -Fx "flutter|$FIXTURE/repo/packages/rohd_devtools_widgets|pub publish --dry-run" "$SDK_LOG"
grep -Fx "dart|$FIXTURE/repo/packages/rohd_source_navigator|pub publish --dry-run" "$SDK_LOG"
grep -Fx "dart|$FIXTURE/repo/packages/rohd_live_debugger|pub publish --dry-run" "$SDK_LOG"

run_case 0 "$HELPER" rohd_source_navigator
[[ "$(cat "$SDK_LOG")" == "dart|$FIXTURE/repo/packages/rohd_source_navigator|pub publish --dry-run" ]]
FAIL_PACKAGE=rohd_source_navigator run_case 1 "$HELPER" rohd_source_navigator rohd_hierarchy
[[ "$(wc -l < "$SDK_LOG")" -eq 2 ]]
grep -F 'rohd_source_navigator: FAILED (exit 65;' "$FIXTURE/output"
grep -F 'rohd_hierarchy: PASSED' "$FIXTURE/output"

export FAIL_PACKAGE=rohd_hierarchy
run_case 1 "$HELPER" rohd_hierarchy rohd_waveform
[[ "$(wc -l < "$SDK_LOG")" -eq 2 ]]
grep -F 'rohd_hierarchy: FAILED (exit 65;' "$FIXTURE/output"
grep -F 'rohd_waveform: PASSED' "$FIXTURE/output"
unset FAIL_PACKAGE

SIGNAL_PARENT=1 SIGNAL_PID_FILE="$FIXTURE/check.pid" PATH="$FIXTURE/bin" \
  /bin/bash "$HELPER" rohd_hierarchy > "$FIXTURE/output" 2>&1 &
check_pid=$!
printf '%s\n' "$check_pid" > "$FIXTURE/check.pid"
status=0
wait "$check_pid" || status=$?
[[ "$status" -eq 143 ]]
cmp "$FIXTURE/original-pubignore" "$FIXTURE/repo/.pubignore"
[[ ! -e "$FIXTURE/repo/.pubignore-release.lock" ]]

mkdir "$FIXTURE/repo/.pubignore-release.lock"
status=0
PATH="$FIXTURE/bin" /bin/bash "$HELPER" rohd_hierarchy > "$FIXTURE/output" 2>&1 || status=$?
[[ "$status" -eq 2 ]]
grep -Fq 'Release check lock exists' "$FIXTURE/output"
cmp "$FIXTURE/original-pubignore" "$FIXTURE/repo/.pubignore"
rmdir "$FIXTURE/repo/.pubignore-release.lock"

status=0
MUTATE_IGNORE=1 PATH="$FIXTURE/bin" /bin/bash "$HELPER" rohd_hierarchy > "$FIXTURE/output" 2>&1 || status=$?
[[ "$status" -eq 1 ]]
grep -Fq 'not overwriting it' "$FIXTURE/output"
grep -Fxq '# concurrent edit' "$FIXTURE/repo/.pubignore"
cmp "$FIXTURE/original-pubignore" "$FIXTURE/repo/.pubignore-release.lock/original"
cp "$FIXTURE/original-pubignore" "$FIXTURE/repo/.pubignore"
rm "$FIXTURE/repo/.pubignore-release.lock/original" "$FIXTURE/repo/.pubignore-release.lock/without-packages"
rmdir "$FIXTURE/repo/.pubignore-release.lock"

rm "$FIXTURE/repo/packages/rohd_live_debugger/extension/devtools/build/index.html"
run_case 1 "$HELPER" rohd rohd_live_debugger
[[ "$(wc -l < "$SDK_LOG")" -eq 1 ]]
grep -F 'rohd_live_debugger: FAILED (missing DevTools payload)' "$FIXTURE/output"
run_case 0 "$HELPER" --validate-only rohd_live_debugger
[[ ! -s "$SDK_LOG" ]]

touch "$FIXTURE/repo/packages/rohd_live_debugger/extension/devtools/build/index.html"
rm "$FIXTURE/repo/packages/rohd_live_debugger/extension/devtools/config.yaml"
run_case 1 "$HELPER" rohd_live_debugger
[[ ! -s "$SDK_LOG" ]]

rm "$FIXTURE/repo/packages/rohd_waveform/pubspec.yaml"
run_case 2 "$HELPER" rohd_hierarchy rohd_waveform
[[ ! -s "$SDK_LOG" ]]
rm "$FIXTURE/repo/packages/rohd_source_navigator/pubspec.yaml"
run_case 2 "$HELPER" rohd_hierarchy rohd_source_navigator
[[ ! -s "$SDK_LOG" ]]
rm "$FIXTURE/bin/flutter"
run_case 2 "$HELPER" rohd_hierarchy rohd_devtools_widgets
[[ ! -s "$SDK_LOG" ]]

run_case 2 "$FIXTURE/repo/tool/release/prepare_release.sh" rohd --force
[[ ! -s "$SDK_LOG" ]]
run_case 2 "$FIXTURE/repo/tool/release/prepare_release.sh"
[[ ! -s "$SDK_LOG" ]]
run_case 2 "$FIXTURE/repo/tool/release/prepare_release.sh" 0.6.11-rc.1
[[ ! -s "$SDK_LOG" ]]
run_case 2 "$FIXTURE/repo/tool/release/prepare_release.sh" rohd_devtools_widgets
[[ ! -s "$SDK_LOG" ]]

echo "$passed checks passed using only fake SDK executables."
