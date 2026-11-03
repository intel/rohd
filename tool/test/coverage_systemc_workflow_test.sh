#!/usr/bin/env bash
# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# coverage_systemc_workflow_test.sh
# Checks coverage tooling remains source-controlled and CI-ready.
#
# 2026 October 24
# Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly WORKFLOW="$REPO_ROOT/.github/workflows/coverage.yml"
readonly GENERAL_WORKFLOW="$REPO_ROOT/.github/workflows/general.yml"
readonly TOOL_README="$REPO_ROOT/tool/README.md"
readonly LINK_CHECK_SCRIPT="$REPO_ROOT/tool/gh_actions/check_markdown_links.sh"

grep -F "ROHD_REQUIRE_SYSTEMC: '1'" "$WORKFLOW" > /dev/null

systemc_line="$(grep -n -m1 'Install Accellera SystemC' "$WORKFLOW" | cut -d: -f1)"
pch_line="$(grep -n -m1 'Pre-build SystemC PCH and Makefile' "$WORKFLOW" | cut -d: -f1)"
coverage_line="$(grep -n -m1 'Generate coverage and badge' "$WORKFLOW" | cut -d: -f1)"

((systemc_line < pch_line && pch_line < coverage_line))

if git -C "$REPO_ROOT" check-ignore -q tool/coverage/generate_coverage.sh; then
  echo 'Coverage tooling must not be ignored as generated coverage output.' >&2
  exit 1
fi
for ignore_file in .gitignore .pubignore; do
  grep -Fx '!tool/coverage/' "$REPO_ROOT/$ignore_file" > /dev/null
  grep -Fx '!tool/coverage/**' "$REPO_ROOT/$ignore_file" > /dev/null
done
grep -F '| [coverage/](./coverage/README.md)' "$TOOL_README" > /dev/null

grep -F 'name: Setup Node for Markdown links' "$GENERAL_WORKFLOW" > /dev/null
grep -F 'node-version: 24' "$GENERAL_WORKFLOW" > /dev/null
grep -F 'run: bash tool/gh_actions/check_markdown_links.sh' \
  "$GENERAL_WORKFLOW" > /dev/null
if grep -F 'gaurav-nelson/github-action-markdown-link-check' \
  "$GENERAL_WORKFLOW" > /dev/null; then
  echo 'The noisy third-party Markdown link action must not be used.' >&2
  exit 1
fi
grep -F 'markdown-link-check@3.8.7' "$LINK_CHECK_SCRIPT" > /dev/null
grep -F "NODE_OPTIONS='--no-deprecation'" "$LINK_CHECK_SCRIPT" > /dev/null
grep -F 'cat "$OUTPUT_FILE"' "$LINK_CHECK_SCRIPT" > /dev/null
grep -F -- '-name .dart_tool -o -name build -o -name node_modules' \
  "$LINK_CHECK_SCRIPT" > /dev/null

echo 'Coverage tooling and workflow checks passed.'
