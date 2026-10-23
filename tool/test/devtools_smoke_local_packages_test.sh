#!/usr/bin/env bash
# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# devtools_smoke_local_packages_test.sh
# Tests prepared viewer selection for DevTools smoke checks.
#
# 2026 October 23
# Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
readonly FIXTURE_REPO="$FIXTURE/repo"
readonly COMMAND_LOG="$FIXTURE/commands.log"
export COMMAND_LOG

mkdir -p \
  "$FIXTURE_REPO/tool/gh_actions/devtool" \
  "$FIXTURE_REPO/tool/devtools"
cp "$REPO_ROOT/tool/gh_actions/devtool/smoke_test_local_packages.sh" \
  "$FIXTURE_REPO/tool/gh_actions/devtool/"

cat > "$FIXTURE_REPO/tool/devtools/devtools_dev_mode.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'configure|%s|%s|%s|%s\n' \
  "$WAVE_VIEWER_GIT_URL" "$WAVE_VIEWER_GIT_REF" "$1" "$2" >> "$COMMAND_LOG"
[[ "$3" == git ]]
EOF

cat > "$FIXTURE_REPO/tool/gh_actions/devtool/install_devtools.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'install\n' >> "$COMMAND_LOG"
EOF

cat > "$FIXTURE_REPO/tool/gh_actions/devtool/test_devtools_install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'verify|%s\n' "$1" >> "$COMMAND_LOG"
EOF

chmod +x \
  "$FIXTURE_REPO/tool/devtools/devtools_dev_mode.sh" \
  "$FIXTURE_REPO/tool/gh_actions/devtool/install_devtools.sh" \
  "$FIXTURE_REPO/tool/gh_actions/devtool/test_devtools_install.sh"

bash "$FIXTURE_REPO/tool/gh_actions/devtool/smoke_test_local_packages.sh"

expected=$'configure|https://github.com/intel/rohd-wave-viewer.git|528178830b081c0aca2e6bbb321372d26725fc59|configure-group|wave-viewer\ninstall\nverify|extension/devtools'
[[ "$(cat "$COMMAND_LOG")" == "$expected" ]]

echo 'DevTools smoke local-package checks passed.'
