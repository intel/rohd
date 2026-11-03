#!/usr/bin/env bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly VERIFIER="$REPO_ROOT/rohd_extension/tool/verify_extension_pack.sh"
readonly FIXTURE="$(mktemp -d)"
readonly MANIFEST="$FIXTURE/package.json"
export CURL_LOG="$FIXTURE/curl.log"
trap 'rm -rf "$FIXTURE"' EXIT

write_manifest() {
  cat > "$MANIFEST" <<'JSON'
{
  "name": "rohd",
  "extensionPack": [
    "intel-corporation.rohd-schematic-viewer",
    "intel-corporation.rohd-wave-viewer"
  ]
}
JSON
}

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

run_case 0 "Verified ROHD viewer extension pack:" bash "$VERIFIER"

write_manifest
run_case 0 "Verified ROHD viewer extension pack:" bash "$VERIFIER" "$MANIFEST"

cat > "$MANIFEST" <<'JSON'
{
  "name": "rohd",
  "extensionPack": [
    "intel-corporation.rohd-schematic-viewer"
  ]
}
JSON
run_case 1 "extensionPack must exactly be" bash "$VERIFIER" "$MANIFEST"

write_manifest
cat > "$FIXTURE/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_LOG"
EOF
chmod +x "$FIXTURE/curl"
: > "$CURL_LOG"
run_case 0 "Verified published Marketplace extension: intel-corporation.rohd-wave-viewer" \
  env CURL="$FIXTURE/curl" bash "$VERIFIER" --verify-published "$MANIFEST"
grep -F "itemName=intel-corporation.rohd-schematic-viewer" "$CURL_LOG" >/dev/null
grep -F "itemName=intel-corporation.rohd-wave-viewer" "$CURL_LOG" >/dev/null

echo "4 extension-pack verifier checks passed."
