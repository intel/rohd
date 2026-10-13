#!/bin/bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# write_local_package_overrides.sh
# Creates ignored local overrides for unpublished monorepo package versions.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

write_override() {
  local file="$1"
  local contents="$2"
  if [[ -e "$file" ]]; then
    return
  fi
  printf '%s\n' "$contents" > "$file"
}

write_override "$REPO_ROOT/pubspec_overrides.yaml" \
'dependency_overrides:
  rohd_hierarchy:
    path: packages/rohd_hierarchy'

write_override \
  "$REPO_ROOT/doc/tutorials/chapter_9/rohd_vf_example/pubspec_overrides.yaml" \
'dependency_overrides:
  rohd:
    path: ../../../../
  rohd_hierarchy:
    path: ../../../../packages/rohd_hierarchy'

write_override \
  "$REPO_ROOT/packages/rohd_devtools_widgets/pubspec_overrides.yaml" \
'dependency_overrides:
  rohd_hierarchy:
    path: ../rohd_hierarchy'
