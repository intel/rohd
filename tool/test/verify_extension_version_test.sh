#!/usr/bin/env bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly FIXTURE="$(mktemp -d)"
readonly EXTENSION="$FIXTURE/rohd_extension"
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p "$EXTENSION"
cp "$REPO_ROOT/rohd_extension/Makefile" "$EXTENSION/Makefile"
cat > "$EXTENSION/pubspec.yaml" <<'YAML'
name: rohd_vscode_extension
publish_to: none
version: 0.2.0
YAML
cat > "$EXTENSION/package.json" <<'JSON'
{
  "name": "rohd",
  "version": "0.2.0",
  "publisher": "intel-corporation"
}
JSON
cat > "$EXTENSION/package-lock.json" <<'JSON'
{
  "name": "rohd",
  "version": "0.2.0",
  "lockfileVersion": 3,
  "packages": {
    "": {
      "name": "rohd",
      "version": "0.2.0"
    }
  }
}
JSON

run_case() {
  local expected_status="$1"
  local expected_message="$2"
  shift 2
  local status=0
  "$@" > "$FIXTURE/output" 2>&1 || status=$?
  if [[ "$status" -ne "$expected_status" ]]; then
    cat "$FIXTURE/output"
    echo "Expected exit $expected_status, got $status" >&2
    exit 1
  fi
  grep -F "$expected_message" "$FIXTURE/output" >/dev/null
}

run_case 0 "Pub and VS Code extension version 0.2.0 verified for intel-corporation.rohd." \
  make -s -C "$EXTENSION" verify-extension-version

sed -i 's/version: 0.2.0/version: 0.2.1/' "$EXTENSION/pubspec.yaml"
run_case 2 "Pub and VS Code extension versions do not match." \
  make -s -C "$EXTENSION" verify-extension-version

sed -i 's/version: 0.2.1/version: 0.2.0/' "$EXTENSION/pubspec.yaml"
sed -i '0,/"version": "0.2.0"/s//"version": "0.2.1"/' "$EXTENSION/package-lock.json"
run_case 2 "Pub and VS Code extension versions do not match." \
  make -s -C "$EXTENSION" verify-extension-version

mkdir -p "$FIXTURE/bin"
export NPM_LOG="$FIXTURE/npm.log"
cat > "$FIXTURE/bin/npm" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s\n' "$PWD" "$*" >> "$NPM_LOG"
EOF
chmod +x "$FIXTURE/bin/npm"
sed -i '0,/"version": "0.2.1"/s//"version": "0.2.0"/' "$EXTENSION/package-lock.json"
PATH="$FIXTURE/bin:$PATH" run_case 0 \
  "Synchronized VS Code extension version 0.2.0 from pubspec.yaml." \
  make -s -C "$EXTENSION" sync-version
[[ "$(cat "$NPM_LOG")" == "$EXTENSION|version 0.2.0 --no-git-tag-version --allow-same-version" ]]

echo "4 extension version synchronization checks passed."
