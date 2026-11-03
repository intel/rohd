#!/usr/bin/env bash
# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# check_markdown_links.sh
# GitHub Actions step: Validate Markdown links with concise successful output.
#
# 2026 October 25
# Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly CONFIG_FILE="$REPO_ROOT/.github/configs/mlc_config.json"
readonly OUTPUT_FILE="$(mktemp)"
trap 'rm -f "$OUTPUT_FILE"' EXIT

cd "$REPO_ROOT"

if ! env \
  NODE_OPTIONS='--no-deprecation' \
  NPM_CONFIG_AUDIT=false \
  NPM_CONFIG_FUND=false \
  NPM_CONFIG_LOGLEVEL=error \
  npm exec --yes --package=markdown-link-check@3.8.7 -- \
  bash -s -- "$CONFIG_FILE" >"$OUTPUT_FILE" 2>&1 <<'CHECKER'; then
set -euo pipefail

readonly config_file="$1"
status=0
while IFS= read -r -d '' markdown_file; do
  markdown-link-check --config "$config_file" --quiet "$markdown_file" ||
    status=1
done < <(
  find . -type d \( -name .dart_tool -o -name build -o -name node_modules \) \
    -prune -o -name '*.md' -print0
)
exit "$status"
CHECKER
  cat "$OUTPUT_FILE"
  exit 1
fi
