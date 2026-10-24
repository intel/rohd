#!/bin/bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# Test the all-package Pana runner with fake commands and no network access.
# Usage: bash tool/test/run_pana_test.sh

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/bin" "$FIXTURE/pub cache/bin"
export REPO_ROOT PANA_LOG="$FIXTURE/pana.log"
ln -s /bin/true "$FIXTURE/pub cache/bin/pana"

cat > "$FIXTURE/bin/bash" <<'EOF'
#!/bin/bash
set -euo pipefail
[[ "$#" -eq 3 && "$1" == "$REPO_ROOT/tool/gh_actions/pana_source.sh" ]]
package="${2##*/}"
case "$package:$3" in
  rohd:dart|rohd_hierarchy:dart|rohd_waveform:dart|\
    rohd_devtools_widgets:flutter|rohd_source_navigator:dart) ;;
  *) exit 99 ;;
esac
printf '%s|%s\n' "$package" "$3" >> "$PANA_LOG"
[[ "${FAIL_PACKAGE:-}" != "$package" ]] || exit 71
EOF
chmod +x "$FIXTURE/bin/bash"

passed=0
run_case() {
  local expected="$1"
  shift
  local status=0
  : > "$PANA_LOG"
  PATH="$FIXTURE/bin:$PATH" PUB_CACHE="$FIXTURE/pub cache" \
    /bin/bash "$REPO_ROOT/tool/run_pana.sh" "$@" \
    >"$FIXTURE/output" 2>&1 || status=$?
  if [[ "$status" -ne "$expected" ]]; then
    cat "$FIXTURE/output"
    echo "Expected exit $expected, got $status for: $*" >&2
    exit 1
  fi
  passed=$((passed + 1))
}

run_case 0
[[ "$(cat "$PANA_LOG")" == $'rohd|dart\nrohd_hierarchy|dart\nrohd_waveform|dart\nrohd_devtools_widgets|flutter\nrohd_source_navigator|dart' ]]

run_case 0 rohd_devtools_widgets rohd_waveform
[[ "$(cat "$PANA_LOG")" == $'rohd_devtools_widgets|flutter\nrohd_waveform|dart' ]]

run_case 2 rohd unsupported
[[ ! -s "$PANA_LOG" ]]

FAIL_PACKAGE=rohd_waveform run_case 71 rohd rohd_waveform rohd_source_navigator
[[ "$(cat "$PANA_LOG")" == $'rohd|dart\nrohd_waveform|dart\nrohd_source_navigator|dart' ]]

echo "$passed all-package Pana runner checks passed using fake commands."
