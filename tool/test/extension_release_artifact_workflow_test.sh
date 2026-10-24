#!/usr/bin/env bash
# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# extension_release_artifact_workflow_test.sh
# Checks the VS Code extension release artifact workflow contract.
#
# 2026 October 24
# Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly WORKFLOW="$REPO_ROOT/.github/workflows/extension_artifact.yml"

grep -F "name: Extension release artifact" "$WORKFLOW" > /dev/null
grep -F "'rohd-vscode-v*.*.*'" "$WORKFLOW" > /dev/null
grep -F "workflow_dispatch:" "$WORKFLOW" > /dev/null
grep -F "make verify-extension-version" "$WORKFLOW" > /dev/null
grep -F "verify_extension_pack.sh --verify-published" "$WORKFLOW" > /dev/null
grep -F "package_vscode.sh" "$WORKFLOW" > /dev/null
grep -F "actions/upload-artifact@v4" "$WORKFLOW" > /dev/null
grep -F "retention-days: 90" "$WORKFLOW" > /dev/null
grep -F "artifact-url" "$WORKFLOW" > /dev/null
grep -F "Do not upload the GitHub ZIP" "$WORKFLOW" > /dev/null
grep -F "does not publish or require Marketplace credentials" "$WORKFLOW" \
  > /dev/null

echo 'VS Code extension release artifact workflow checks passed.'
