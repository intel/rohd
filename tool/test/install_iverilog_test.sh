#!/usr/bin/env bash
# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# install_iverilog_test.sh
# Tests Icarus Verilog installation refreshes apt metadata first.
#
# 2026 October 23
# Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
readonly INSTALL_LOG="$FIXTURE/install.log"
export INSTALL_LOG

mkdir -p "$FIXTURE/bin"
cat > "$FIXTURE/bin/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'sudo|%s\n' "$*" >> "$INSTALL_LOG"
"$@"
EOF

cat > "$FIXTURE/bin/apt-get" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'apt-get|%s\n' "$*" >> "$INSTALL_LOG"
EOF

chmod +x "$FIXTURE/bin/sudo" "$FIXTURE/bin/apt-get"
PATH="$FIXTURE/bin:$PATH" bash "$REPO_ROOT/tool/gh_actions/install_iverilog.sh"

expected=$'sudo|apt-get update -qq\napt-get|update -qq\nsudo|apt-get install --yes iverilog\napt-get|install --yes iverilog'
[[ "$(cat "$INSTALL_LOG")" == "$expected" ]]

echo 'Icarus Verilog installer checks passed.'
