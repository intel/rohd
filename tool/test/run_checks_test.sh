#!/bin/bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# run_checks_test.sh
# Test optional test-suite execution while retaining other project checks.
# Uses temporary stubs only; no real SDK, simulator, or publication commands run.
#
# Usage (from repo root):
#   bash tool/test/run_checks_test.sh
#
# 2026 September 18
# Author: Max Korbel <max.korbel@intel.com>

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
export CHECK_LOG="$FIXTURE/checks.log"

mkdir -p "$FIXTURE/tool/gh_actions" "$FIXTURE/bin"
cp "$REPO_ROOT/tool/run_checks.sh" "$FIXTURE/tool/"
printf '%s\n' '#!/bin/bash' 'exit 0' > "$FIXTURE/bin/tput"
printf '%s\n' '#!/bin/bash' 'printf "iverilog\n" >> "$CHECK_LOG"' \
  'exit "${IVERILOG_STATUS:-0}"' > "$FIXTURE/bin/which"
printf '%s\n' '#!/bin/bash' 'printf "verilator\n" >> "$CHECK_LOG"' > "$FIXTURE/bin/verilator"
chmod +x "$FIXTURE/bin/"*
for step in install_dependencies verify_formatting analyze_source generate_documentation run_tests check_tmp_test; do
  printf '%s\n' '#!/bin/bash' \
    'step="${0##*/}"' \
    'printf "%s\n" "$step" >> "$CHECK_LOG"' \
    'if [[ "${FAIL_STEP:-}" == "$step" ]]; then exit 71; fi' \
    'exit 0' > "$FIXTURE/tool/gh_actions/$step.sh"
  chmod +x "$FIXTURE/tool/gh_actions/$step.sh"
done
cd "$FIXTURE"

passed=0
run_case() {
  local expected="$1"
  shift
  local status=0
  : > "$CHECK_LOG"
  PATH="$FIXTURE/bin" /bin/bash tool/run_checks.sh "$@" > "$FIXTURE/output" 2>&1 || status=$?
  if [[ "$status" -ne "$expected" ]]; then
    cat "$FIXTURE/output"
    echo "Expected exit $expected, got $status for: $*" >&2
    exit 1
  fi
  passed=$((passed + 1))
}

readonly COMMON_STEPS=$'install_dependencies.sh\nverify_formatting.sh\nanalyze_source.sh\ngenerate_documentation.sh'
run_case 0
[[ "$(cat "$CHECK_LOG")" == "$COMMON_STEPS"$'\niverilog\nverilator\nrun_tests.sh\ncheck_tmp_test.sh' ]]

run_case 0 --skip-tests
[[ "$(cat "$CHECK_LOG")" == "$COMMON_STEPS"$'\ncheck_tmp_test.sh' ]]
grep -Fq 'Skipping tests and simulator prerequisites' "$FIXTURE/output"

export FAIL_STEP=run_tests.sh
run_case 71
[[ "$(cat "$CHECK_LOG")" == "$COMMON_STEPS"$'\niverilog\nverilator\nrun_tests.sh' ]]
run_case 0 --skip-tests
unset FAIL_STEP

rm "$FIXTURE/bin/verilator"
export IVERILOG_STATUS=1 ROHD_REQUIRE_VERILATOR=1
run_case 0 --skip-tests
[[ "$(cat "$CHECK_LOG")" == "$COMMON_STEPS"$'\ncheck_tmp_test.sh' ]]
run_case 1
[[ "$(cat "$CHECK_LOG")" == "$COMMON_STEPS"$'\niverilog' ]]
unset IVERILOG_STATUS ROHD_REQUIRE_VERILATOR

export FAIL_STEP=analyze_source.sh
run_case 71 --skip-tests
[[ "$(cat "$CHECK_LOG")" == $'install_dependencies.sh\nverify_formatting.sh\nanalyze_source.sh' ]]
unset FAIL_STEP

run_case 2 --unknown
[[ ! -s "$CHECK_LOG" ]]
run_case 2 --skip-tests unexpected
[[ ! -s "$CHECK_LOG" ]]

echo "$passed project-check cases passed using isolated stubs."