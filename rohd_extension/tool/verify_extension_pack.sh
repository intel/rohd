#!/usr/bin/env bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause

set -euo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly EXTENSION_PACK=(
  intel-corporation.rohd-schematic-viewer
  intel-corporation.rohd-wave-viewer
)

usage() {
  cat >&2 <<'USAGE'
Usage: verify_extension_pack.sh [--verify-published] [package.json]

Verify the ROHD viewer extension pack. --verify-published also checks that each
viewer has a public Visual Studio Marketplace listing.
USAGE
}

verify_published=false
manifest="$ROOT/package.json"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --verify-published)
      verify_published=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      usage
      exit 2
      ;;
    *)
      manifest="$1"
      ;;
  esac
  shift
done

if [[ ! -f "$manifest" ]]; then
  echo "error: Extension manifest not found: $manifest" >&2
  exit 2
fi
if ! command -v node >/dev/null; then
  echo "error: Required command not found: node" >&2
  exit 2
fi

node - "$manifest" "${EXTENSION_PACK[@]}" <<'NODE'
const {readFileSync} = require('node:fs');

const [manifestPath, ...expectedPack] = process.argv.slice(2);
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));

function fail(message) {
  console.error(`error: ${message}`);
  process.exit(1);
}

if (JSON.stringify(manifest.extensionPack) !== JSON.stringify(expectedPack)) {
  fail(
    `extensionPack must exactly be ${expectedPack.join(', ')}`,
  );
}
if (manifest.extensionDependencies?.length) {
  fail('ROHD viewer extensions must use extensionPack, not extensionDependencies');
}
for (const extensionId of manifest.extensionPack) {
  if (!/^[a-z0-9-]+\.[a-z0-9-]+$/.test(extensionId)) {
    fail(`Invalid Marketplace extension ID: ${extensionId}`);
  }
}
NODE

echo "Verified ROHD viewer extension pack: ${EXTENSION_PACK[*]}"

if [[ "$verify_published" == false ]]; then
  exit 0
fi

curl_bin="${CURL:-curl}"
if ! command -v "$curl_bin" >/dev/null; then
  echo "error: Required command not found: $curl_bin" >&2
  exit 2
fi

for extension_id in "${EXTENSION_PACK[@]}"; do
  if ! "$curl_bin" --fail --location --silent --show-error \
    "https://marketplace.visualstudio.com/items?itemName=$extension_id" \
    >/dev/null; then
    echo "error: Marketplace extension is not publicly available: $extension_id" >&2
    exit 1
  fi
  echo "Verified published Marketplace extension: $extension_id"
done
