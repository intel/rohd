#!/usr/bin/env bash
# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# run_gh_codespaces_setup_test.sh
# Tests Flutter PATH propagation in the Codespaces setup workflow.
#
# 2026 October 22
# Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
readonly SETUP_LOG="$FIXTURE/setup.log"
export SETUP_LOG

mkdir -p "$FIXTURE/repo/tool/gh_codespaces" "$FIXTURE/repo/tool/gh_actions"
cp "$REPO_ROOT/tool/gh_codespaces/run_setup.sh" \
  "$FIXTURE/repo/tool/gh_codespaces/"

cat > "$FIXTURE/repo/tool/gh_codespaces/install_flutter.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'install_flutter\n' >> "$SETUP_LOG"
if [[ "${CREATE_FLUTTER:-1}" != 1 ]]; then
  exit 0
fi
flutter_root="${FLUTTER_ROOT:-$HOME/flutter}"
mkdir -p "$flutter_root/bin"
cat > "$flutter_root/bin/flutter" <<'FLUTTER'
#!/usr/bin/env bash
printf 'flutter|%s\n' "$*" >> "$SETUP_LOG"
FLUTTER
chmod +x "$flutter_root/bin/flutter"
EOF

cat > "$FIXTURE/repo/tool/gh_actions/install_dependencies.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'install_dependencies\n' >> "$SETUP_LOG"
[[ "$(command -v flutter)" == "$FLUTTER_ROOT/bin/flutter" ]]
flutter pub get
EOF

for script in install_iverilog.sh install_verilator.sh install_systemc.sh install_node.sh; do
  directory="$FIXTURE/repo/tool/gh_actions"
  if [[ "$script" == install_systemc.sh ]]; then
    directory="$FIXTURE/repo/tool/gh_codespaces"
  fi
  cat > "$directory/$script" <<EOF
#!/usr/bin/env bash
printf '${script%.sh}\\n' >> "\$SETUP_LOG"
EOF
done

chmod +x \
  "$FIXTURE/repo/tool/gh_codespaces/install_flutter.sh" \
  "$FIXTURE/repo/tool/gh_codespaces/install_systemc.sh" \
  "$FIXTURE/repo/tool/gh_actions/"*.sh

run_case() {
  local expected_status="$1"
  local create_flutter="$2"
  local home="$FIXTURE/home-$create_flutter"
  local status=0
  : > "$SETUP_LOG"
  (
    cd "$FIXTURE/repo"
    env -u FLUTTER_ROOT \
      HOME="$home" \
      SETUP_LOG="$SETUP_LOG" \
      PATH="$FIXTURE/bin:/usr/bin:/bin" \
      CREATE_FLUTTER="$create_flutter" \
      bash tool/gh_codespaces/run_setup.sh
  ) > "$FIXTURE/output" 2>&1 || status=$?
  if [[ "$status" -ne "$expected_status" ]]; then
    cat "$FIXTURE/output"
    echo "Expected exit $expected_status, got $status." >&2
    exit 1
  fi
}

run_case 0 1
expected=$'install_flutter\ninstall_dependencies\nflutter|pub get\ninstall_iverilog\ninstall_verilator\ninstall_systemc\ninstall_node'
[[ "$(cat "$SETUP_LOG")" == "$expected" ]]

run_case 1 0
grep -F 'Flutter was not found after installation' "$FIXTURE/output" > /dev/null
[[ "$(cat "$SETUP_LOG")" == 'install_flutter' ]]

echo 'Codespaces Flutter setup checks passed.'
