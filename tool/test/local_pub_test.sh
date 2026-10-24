#!/usr/bin/env bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/local-pub-test.XXXXXXXX")"
trap 'rm -rf "$fixture"' EXIT
runner="$repo_root/tool/local_pub.sh"
unset LOCAL_PUB_URL

bash "$runner" --help >"$fixture/help"
grep -Fq 'server must already be running' "$fixture/help"
if bash "$runner" >"$fixture/error" 2>&1; then
  echo 'Missing arguments unexpectedly succeeded.' >&2
  exit 1
fi

export PUB_CACHE="$fixture/original-cache"
export PUB_HOSTED_URL=https://pub.dev
export EXPECTED_EXPERIMENT="$fixture/experiment with spaces"
export EXPECTED_PWD="$PWD"
bash "$runner" "$EXPECTED_EXPERIMENT" bash -c '
  set -euo pipefail
  [[ "$PUB_CACHE" == "$EXPECTED_EXPERIMENT/pub-cache" ]]
  [[ "$PUB_HOSTED_URL" == http://localhost:8081 ]]
  [[ -d "$PUB_CACHE" ]]
  [[ "$PWD" == "$EXPECTED_PWD" ]]
  [[ "$1" == "argument with spaces" ]]
' -- 'argument with spaces'
[[ "$PUB_CACHE" == "$fixture/original-cache" ]]
[[ "$PUB_HOSTED_URL" == https://pub.dev ]]

for url in http://127.0.0.1:18081/ 'http://[::1]:18081'; do
  LOCAL_PUB_URL="$url" bash "$runner" "$EXPECTED_EXPERIMENT" bash -c '
    [[ "$PUB_HOSTED_URL" == "${LOCAL_PUB_URL%/}" ]]
  '
done

for url in https://pub.dev http://example.com:8081 http://localhost:0 \
  http://localhost:65536 http://localhost:8081/path http://user@localhost:8081; do
  if LOCAL_PUB_URL="$url" bash "$runner" "$fixture/invalid" true \
    >"$fixture/error" 2>&1; then
    echo "Unexpectedly accepted registry: $url" >&2
    exit 1
  fi
  grep -Fq 'error: LOCAL_PUB_URL' "$fixture/error"
  [[ ! -e "$fixture/invalid" ]]
done

set +e
bash "$runner" "$EXPECTED_EXPERIMENT" bash -c 'exit 37'
status=$?
set -e
[[ "$status" -eq 37 ]]

echo 'Local Pub environment checks passed.'
