#!/bin/bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# package_vscode_test.sh
# Test VSIX packaging commands, prerequisites, and failure handling.
# Uses temporary files and fake npm/Node executables on a restricted PATH;
# no real dependency installs, extension installs, or publication commands run.
#
# Usage (from repo root):
#   bash tool/test/package_vscode_test.sh
#
# 2026 September 18
# Author: Max Korbel <max.korbel@intel.com>

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
readonly HELPER="$FIXTURE/repo/tool/package_vscode.sh"
readonly OUTPUT="$FIXTURE/output space/check.vsix"
export NPM_LOG="$FIXTURE/npm.log"

mkdir -p "$FIXTURE/repo/tool" "$FIXTURE/repo/rohd_extension" "$FIXTURE/bin"
cp "$REPO_ROOT/tool/package_vscode.sh" "$HELPER"
for executable in dirname mkdir; do
  ln -s "$(command -v "$executable")" "$FIXTURE/bin/$executable"
done
ln -s /bin/true "$FIXTURE/bin/node"
printf '%s\n' '#!/bin/bash' \
  'printf "%s|%s\n" "$PWD" "$*" >> "$NPM_LOG"' \
  'if [[ "$#" -eq 1 && "$1" == ci ]]; then' \
  '  exit "${INSTALL_STATUS:-0}"' \
  'fi' \
  '[[ "$#" -eq 5 && "$1" == run && "$2" == package && "$3" == -- && "$4" == --out ]] || exit 99' \
  '[[ "${PACKAGE_STATUS:-0}" -eq 0 ]] || exit "$PACKAGE_STATUS"' \
  'case "${PAYLOAD:-present}" in' \
  '  present) printf "fixture vsix\n" > "$5" ;;' \
  '  empty) : > "$5" ;;' \
  '  missing) ;;' \
  '  *) exit 99 ;;' \
  'esac' > "$FIXTURE/bin/npm"
chmod +x "$FIXTURE/bin/npm"
cd "$FIXTURE"

passed=0
run_case() {
  local expected="$1"
  shift
  local status=0
  : > "$NPM_LOG"
  PATH="$FIXTURE/bin" /bin/bash "$HELPER" "$@" > "$FIXTURE/output.log" 2>&1 || status=$?
  if [[ "$status" -ne "$expected" ]]; then
    cat "$FIXTURE/output.log"
    echo "Expected exit $expected, got $status for: $*" >&2
    exit 1
  fi
  passed=$((passed + 1))
}

run_case 2
run_case 2 relative.vsix
run_case 2 "$OUTPUT" --force
run_case 2 "$FIXTURE/not-a-vsix.zip"
[[ ! -s "$NPM_LOG" ]]

run_case 0 "$OUTPUT"
[[ "$(cat "$OUTPUT")" == 'fixture vsix' ]]
[[ "$(cat "$NPM_LOG")" == "$FIXTURE/repo/rohd_extension|ci"$'\n'"$FIXTURE/repo/rohd_extension|run package -- --out $OUTPUT" ]]
run_case 2 "$OUTPUT"
[[ ! -s "$NPM_LOG" && "$(cat "$OUTPUT")" == 'fixture vsix' ]]
rm "$OUTPUT"
ln -s "$FIXTURE/missing.vsix" "$OUTPUT"
run_case 2 "$OUTPUT"
[[ ! -s "$NPM_LOG" ]]
rm "$OUTPUT"

INSTALL_STATUS=71 run_case 71 "$OUTPUT"
[[ "$(cat "$NPM_LOG")" == "$FIXTURE/repo/rohd_extension|ci" ]]
PACKAGE_STATUS=72 run_case 72 "$OUTPUT"
[[ ! -e "$OUTPUT" ]]
PAYLOAD=missing run_case 1 "$OUTPUT"
PAYLOAD=empty run_case 1 "$OUTPUT"
rm "$OUTPUT"

mv "$FIXTURE/bin/node" "$FIXTURE/node"
run_case 2 "$OUTPUT"
[[ ! -s "$NPM_LOG" ]]
mv "$FIXTURE/node" "$FIXTURE/bin/node"
rm "$FIXTURE/bin/npm"
run_case 2 "$OUTPUT"
[[ ! -s "$NPM_LOG" ]]

echo "$passed VSIX packaging checks passed using only fake npm/Node executables."