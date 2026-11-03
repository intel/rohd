#!/bin/bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# setup_systemc_pch_test.sh
# Tests SystemC PCH C++ standard detection with pipefail enabled.
#
# 2026 October
# Author: ROHD Contributors

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p "$FIXTURE/bin" "$FIXTURE/include" "$FIXTURE/lib"
cp "$REPO_ROOT/tool/gh_actions/setup_systemc_pch.sh" "$FIXTURE/"
touch "$FIXTURE/include/systemc.h" "$FIXTURE/lib/libsystemc.so"

cat > "$FIXTURE/bin/nm" <<'EOF'
#!/bin/bash
if [[ "${NM_HAS_CXX20:-0}" == 1 ]]; then
  printf '%s\n' '00000000 T sc_api_version_cxx202002L'
fi
awk 'BEGIN { for (i = 0; i < 20000; i++) print "00000000 T filler_symbol_" i }'
EOF

cat > "$FIXTURE/bin/g++" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$CXX_LOG"
while (($#)); do
  if [[ "$1" == -o ]]; then
    shift
    touch "$1"
    exit 0
  fi
  shift
done
exit 2
EOF
chmod +x "$FIXTURE/bin/nm" "$FIXTURE/bin/g++"

run_case() {
  local has_cxx20="$1"
  local expected_standard="$2"
  rm -rf "$FIXTURE/tmp_test"
  : > "$FIXTURE/cxx.log"
  (
    cd "$FIXTURE"
    PATH="$FIXTURE/bin:/usr/bin:/bin" \
      NM_HAS_CXX20="$has_cxx20" \
      CXX_LOG="$FIXTURE/cxx.log" \
      SYSTEMC_INCLUDE="$FIXTURE/include" \
      SYSTEMC_LIB="$FIXTURE/lib" \
      bash setup_systemc_pch.sh
  )
  grep -F -- "-std=$expected_standard" "$FIXTURE/cxx.log" >/dev/null
  [[ -f "$FIXTURE/tmp_test/pch/systemc.h.gch" ]]
}

# The C++20 marker appears before enough trailing output to exceed a pipe
# buffer. An early-exiting grep would give nm SIGPIPE under pipefail.
run_case 1 c++20
run_case 0 c++17

echo '2 SystemC PCH standard-detection cases passed.'
