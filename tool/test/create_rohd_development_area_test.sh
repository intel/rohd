#!/usr/bin/env bash
# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# create_rohd_development_area_test.sh
# Tests the generated ROHD development-area template without Pub resolution.
#
# 2026 October 22
# Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly GENERATOR="$REPO_ROOT/tool/create_rohd_development_area.sh"
readonly FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
readonly ROHD="$FIXTURE/rohd"
readonly HCL="$FIXTURE/rohd-hcl"
readonly DESTINATION="$FIXTURE/development area"

mkdir -p "$ROHD/packages/rohd_hierarchy" "$HCL"
cat > "$ROHD/pubspec.yaml" <<'YAML'
name: rohd
version: 0.6.11
YAML
cat > "$ROHD/packages/rohd_hierarchy/pubspec.yaml" <<'YAML'
name: rohd_hierarchy
version: 0.1.1
YAML
cat > "$HCL/pubspec.yaml" <<'YAML'
name: rohd_hcl
version: 0.3.0
YAML

"$GENERATOR" --help > "$FIXTURE/help"
grep -F 'ROHD-HCL component support' "$FIXTURE/help" > /dev/null

"$GENERATOR" "$DESTINATION" \
  --package-name starter_ports \
  --module-name StarterPorts \
  --rohd-path "$ROHD" \
  --hcl-path "$HCL"

readonly PUBSPEC="$DESTINATION/pubspec.yaml"
readonly MODULE="$DESTINATION/lib/src/starter_ports.dart"
readonly TEST="$DESTINATION/test/starter_ports_test.dart"

grep -F 'name: starter_ports' "$PUBSPEC" > /dev/null
grep -F 'rohd_hcl: ^0.3.0' "$PUBSPEC" > /dev/null
grep -F 'TypedLogicArray<StarterPortsPacket, LogicValue>' "$MODULE" > /dev/null
grep -F 'addInterface(' "$MODULE" > /dev/null
grep -F 'class _StarterPortsPortInverter extends Module' "$MODULE" > /dev/null
grep -F 'Logic get flag' "$MODULE" > /dev/null
grep -F 'SourceTracer.activate();' "$TEST" > /dev/null
grep -F 'NetlistSynthesizerConfiguration(' "$TEST" > /dev/null
grep -F 'trace: true' "$TEST" > /dev/null
grep -F 'SystemVerilogService(' "$TEST" > /dev/null
grep -F 'TraceService(' "$TEST" > /dev/null
grep -F 'dumpWaves(outputPath: waveformPath);' "$TEST" > /dev/null

cmp "$REPO_ROOT/doc/Component.md" "$DESTINATION/doc/Component.md"
cmp "$REPO_ROOT/.github/skills/rohd-hardware/SKILL.md" \
  "$DESTINATION/.github/skills/rohd-hardware/SKILL.md"
cmp "$REPO_ROOT/.github/skills/rohd-hierarchy/SKILL.md" \
  "$DESTINATION/.github/skills/rohd-hierarchy/SKILL.md"

echo 'ROHD development-area generator checks passed.'
