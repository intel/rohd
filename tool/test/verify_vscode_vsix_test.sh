#!/usr/bin/env bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly EXTENSION="$REPO_ROOT/rohd_extension"
readonly VERIFIER="$EXTENSION/tool/verify_marketplace_vsix.sh"
readonly FIXTURE="$(mktemp -d)"
readonly ARCHIVE="$FIXTURE/archive"
readonly VSIX="$FIXTURE/rohd.vsix"
trap 'rm -rf "$FIXTURE"' EXIT

for executable in node unzip zip; do
  command -v "$executable" >/dev/null || {
    echo "Missing required test command: $executable" >&2
    exit 2
  }
done

extension_name="$(node -p "require('$EXTENSION/package.json').name")"
extension_version="$(node -p "require('$EXTENSION/package.json').version")"
extension_publisher="$(node -p "require('$EXTENSION/package.json').publisher")"

make_vsix() {
  rm -rf "$ARCHIVE" "$VSIX"
  mkdir -p \
    "$ARCHIVE/extension/out" \
    "$ARCHIVE/extension/resources" \
    "$ARCHIVE/extension/snippets" \
    "$ARCHIVE/extension/node_modules/ws"
  printf '<Types/>\n' > "$ARCHIVE/[Content_Types].xml"
  cat > "$ARCHIVE/extension.vsixmanifest" <<EOF
<PackageManifest>
  <Metadata>
    <Identity Id="$extension_name" Version="$extension_version" Publisher="$extension_publisher" />
  </Metadata>
</PackageManifest>
EOF
  cp "$EXTENSION/package.json" "$ARCHIVE/extension/package.json"
  printf 'license\n' > "$ARCHIVE/extension/LICENSE.txt"
  printf '# ROHD\n' > "$ARCHIVE/extension/readme.md"
  printf '# Changelog\n' > "$ARCHIVE/extension/changelog.md"
  printf 'exports.activate = () => {};\n' > "$ARCHIVE/extension/out/extension.js"
  printf '{"ROHD": {}}\n' > "$ARCHIVE/extension/snippets/rohd.json"
  printf '\x89PNG\r\n\x1a\n' > "$ARCHIVE/extension/resources/rohd_icon.png"
  printf 'module.exports = {};\n' > "$ARCHIVE/extension/node_modules/ws/index.js"
  (cd "$ARCHIVE" && zip -qr "$VSIX" .)
}

expect_verification() {
  local expected_status="$1"
  local expected_message="$2"
  shift 2
  make_vsix
  "$@"

  local status=0
  bash "$VERIFIER" "$VSIX" > "$FIXTURE/output" 2>&1 || status=$?
  if [[ "$status" -ne "$expected_status" ]]; then
    cat "$FIXTURE/output"
    echo "Expected verifier exit $expected_status, got $status" >&2
    exit 1
  fi
  grep -F "$expected_message" "$FIXTURE/output" >/dev/null
}

keep_archive() {
  :
}

remove_runtime_dependency() {
  rm "$ARCHIVE/extension/node_modules/ws/index.js"
  rm -f "$VSIX"
  (cd "$ARCHIVE" && zip -qr "$VSIX" .)
}

add_source_file() {
  mkdir -p "$ARCHIVE/extension/src"
  printf 'export {};\n' > "$ARCHIVE/extension/src/extension.ts"
  (cd "$ARCHIVE" && zip -qr "$VSIX" .)
}

add_pub_tooling() {
  mkdir -p "$ARCHIVE/extension/.dart_tool"
  printf '{}\n' > "$ARCHIVE/extension/.dart_tool/package_config.json"
  (cd "$ARCHIVE" && zip -qr "$VSIX" .)
}

expect_verification 0 "Verified Marketplace VSIX: $extension_publisher.$extension_name $extension_version" \
  keep_archive
expect_verification 1 "VSIX is missing required entry: extension/node_modules/ws/index.js" \
  remove_runtime_dependency
expect_verification 1 "VSIX contains excluded development content: extension/src/" \
  add_source_file
expect_verification 1 "VSIX contains excluded development content: extension/.dart_tool/" \
  add_pub_tooling

echo "4 Marketplace VSIX verifier checks passed."
