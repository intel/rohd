#!/bin/bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# Check DevTools command directories without building or accessing the network.
# Usage: bash tool/test/devtools_workspace_test.sh

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
readonly WORKSPACE="$FIXTURE/workspace with spaces"
readonly EXTENSION="$WORKSPACE/rohd_devtools_extension"
mkdir -p "$FIXTURE/bin" "$EXTENSION/scripts"
cp "$REPO_ROOT/rohd_devtools_extension/scripts/devtools_run.sh" "$EXTENSION/scripts/"
printf '#!/bin/bash\nexit 0\n' > "$EXTENSION/scripts/free_ports.sh"
export COMMAND_LOG="$FIXTURE/commands"

cat > "$FIXTURE/bin/flutter" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s|flutter %s\n' "$PWD" "$*" >> "$COMMAND_LOG"
if [[ "$1" == pub && "${FAIL_PUB:-0}" != 0 ]]; then
  exit "$FAIL_PUB"
fi
EOF
cat > "$FIXTURE/bin/make" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s|make %s\n' "$PWD" "$*" >> "$COMMAND_LOG"
EOF
chmod +x "$FIXTURE/bin/flutter" "$FIXTURE/bin/make"

passed=0
run_case() {
  local expected="$1"
  shift
  local status=0
  : > "$COMMAND_LOG"
  (cd "$FIXTURE" && PATH="$FIXTURE/bin:$PATH" \
    bash "$EXTENSION/scripts/devtools_run.sh" "$@") \
    > "$FIXTURE/output" 2>&1 || status=$?
  if [[ "$status" -ne "$expected" ]]; then
    cat "$FIXTURE/output"
    echo "Expected exit $expected, got $status for: $*" >&2
    exit 1
  fi
  passed=$((passed + 1))
}

for mode in web-debug web-release linux-debug linux-release; do
  run_case 0 "$mode"
  expected="$WORKSPACE|flutter pub get"
  case "$mode" in
    web-debug)
      expected+=$'\n'"$EXTENSION|make web-run"
      ;;
    web-release)
      expected+=$'\n'"$EXTENSION|make web/dart_wellen"
      expected+=$'\n'"$EXTENSION|flutter run --release -d web-server --web-port=9099 --web-hostname=127.0.0.1 lib/main_standalone.dart"
      ;;
    linux-debug)
      expected+=$'\n'"$EXTENSION|make assets/.staged"
      expected+=$'\n'"$EXTENSION|flutter run -d linux lib/main_standalone.dart"
      ;;
    linux-release)
      expected+=$'\n'"$EXTENSION|make assets/.staged"
      expected+=$'\n'"$EXTENSION|flutter run --release -d linux lib/main_standalone.dart"
      ;;
  esac
  [[ "$(cat "$COMMAND_LOG")" == "$expected" ]]
done

for argument in --help help -h; do
  run_case 0 "$argument"
  [[ ! -s "$COMMAND_LOG" ]]
done
run_case 2
[[ ! -s "$COMMAND_LOG" ]]
run_case 2 invalid-mode
[[ ! -s "$COMMAND_LOG" ]]
FAIL_PUB=71 run_case 71 web-debug
[[ "$(cat "$COMMAND_LOG")" == "$WORKSPACE|flutter pub get" ]]

# Dry-run normal app targets, including their dependency preparation.
for target in build/web/index.html web-run web-run-profile \
  build/linux/release build/extension/web/index.html; do
  make -s -n -C "$REPO_ROOT/rohd_devtools_extension" \
    -W pubspec.yaml "$target" > "$FIXTURE/make-output"
  grep -F "cd \"$REPO_ROOT\" && flutter pub get" "$FIXTURE/make-output" > /dev/null
  if grep -Fx 'flutter pub get' "$FIXTURE/make-output"; then
    echo "Pub must run from the workspace root for $target" >&2
    exit 1
  fi
  if grep -E 'cargo |wasm-pack |flutter_rust_bridge_codegen |make.* (wasm|prepare)' "$FIXTURE/make-output"; then
    echo "DevTools must consume prepared dependencies for $target" >&2
    exit 1
  fi
  passed=$((passed + 1))
done

make -s -n -C "$REPO_ROOT/rohd_devtools_extension" real-clean > "$FIXTURE/clean-output"
if grep -E 'cd \$\$widget|find \$\$widget|make .*real-clean' "$FIXTURE/clean-output"; then
  echo 'DevTools cleanup must not mutate external viewer packages' >&2
  exit 1
fi
passed=$((passed + 1))

if ! grep -Fq "! -path 'test/integration/*'" \
  "$REPO_ROOT/tool/gh_actions/devtool/run_devtool_test.sh"; then
  echo 'Browser test selection must exclude VM-only integration tests' >&2
  exit 1
fi
passed=$((passed + 1))

for target in coverage coverage-view coverage-clean; do
  make -s -n -C "$REPO_ROOT/rohd_devtools_extension" "$target" \
    > "$FIXTURE/coverage-output"
  case "$target" in
    coverage)
      grep -F "bash \"$REPO_ROOT/tool/generate_coverage.sh\"" \
        "$FIXTURE/coverage-output" > /dev/null
      ;;
    coverage-view)
      grep -F "bash \"$REPO_ROOT/tool/view_coverage.sh\"" \
        "$FIXTURE/coverage-output" > /dev/null
      ;;
    coverage-clean)
      grep -F "rm -rf \"$REPO_ROOT/rohd_devtools_extension/coverage\"" \
        "$FIXTURE/coverage-output" > /dev/null
      ;;
  esac
  if grep -E 'cargo |wasm-pack |flutter_rust_bridge_codegen' \
    "$FIXTURE/coverage-output"; then
    echo "DevTools coverage target must not build viewer dependencies" >&2
    exit 1
  fi
  passed=$((passed + 1))
done

cp "$REPO_ROOT/rohd_devtools_extension/scripts/install_viewer_artifacts.sh" "$EXTENSION/scripts/"
mkdir -p "$WORKSPACE/.dart_tool" "$FIXTURE/dart_wellen/lib/src/rust"
mkdir -p "$FIXTURE/dart_wellen/tool"
printf 'import sys\nassert sys.argv[1:] == ["install"]\n' > "$FIXTURE/dart_wellen/tool/bridge_artifacts.py"
export TEST_WORKSPACE="$WORKSPACE" TEST_DART_WELLEN="$FIXTURE/dart_wellen"
cat > "$FIXTURE/bin/dart" <<'EOF'
#!/bin/bash
set -euo pipefail
[[ "$2" == "$TEST_WORKSPACE/.dart_tool/package_config.json" ]]
[[ "$3" == dart_wellen ]]
printf '%s\n' "$TEST_DART_WELLEN"
EOF
cat > "$FIXTURE/bin/cargo" <<'EOF'
#!/bin/bash
echo 'Unexpected Cargo invocation' >> "$COMMAND_LOG"
exit 99
EOF
chmod +x "$FIXTURE/bin/dart" "$FIXTURE/bin/cargo"

for state in missing partial complete; do
  case "$state" in
    partial) touch "$TEST_DART_WELLEN/lib/src/rust/frb_generated.dart" ;;
    complete) touch "$TEST_DART_WELLEN/lib/src/rust/api.dart" \
      "$TEST_DART_WELLEN/lib/src/rust/frb_generated.io.dart" \
      "$TEST_DART_WELLEN/lib/src/rust/frb_generated.web.dart" ;;
  esac
  status=0
  : > "$COMMAND_LOG"
  PATH="$FIXTURE/bin:$PATH" bash "$EXTENSION/scripts/install_viewer_artifacts.sh" \
    > "$FIXTURE/output" 2>&1 || status=$?
  if [[ "$state" == complete ]]; then
    [[ "$status" -eq 0 ]]
  else
    [[ "$status" -eq 1 ]]
    grep -F 'Missing packaged artifact:' "$FIXTURE/output" > /dev/null
    grep -F 'DevTools does not generate bindings or build Rust dependencies.' "$FIXTURE/output" > /dev/null
  fi
  [[ ! -s "$COMMAND_LOG" ]]
  passed=$((passed + 1))
done

cp "$REPO_ROOT/rohd_devtools_extension/scripts/stage_assets.sh" "$EXTENSION/scripts/"
export TEST_SCHEMATIC="$FIXTURE/schematic" TEST_WAVE_VIEWER="$FIXTURE/viewer"
mkdir -p "$TEST_SCHEMATIC" "$TEST_WAVE_VIEWER" "$TEST_DART_WELLEN/web/pkg" \
  "$EXTENSION/web/dart_wellen"
cat > "$FIXTURE/bin/dart" <<'EOF'
#!/bin/bash
set -euo pipefail
[[ "$2" == "$TEST_WORKSPACE/.dart_tool/package_config.json" ]]
case "$3" in
  dart_wellen) printf '%s\n' "$TEST_DART_WELLEN" ;;
  rohd_schematic_viewer) printf '%s\n' "$TEST_SCHEMATIC" ;;
  rohd_wave_viewer) printf '%s\n' "$TEST_WAVE_VIEWER" ;;
  *) exit 99 ;;
esac
EOF
for artifact in wellen_bridge.js wellen_bridge_bg.wasm LICENSE wellen_bridge_LICENSES.txt; do
  printf 'old runtime\n' > "$EXTENSION/web/dart_wellen/$artifact"
  printf 'selected runtime\n' > "$TEST_DART_WELLEN/web/pkg/$artifact"
done
for selection in first second; do
  printf '%s runtime\n' "$selection" > "$TEST_DART_WELLEN/web/pkg/wellen_bridge_bg.wasm"
  PATH="$FIXTURE/bin:$PATH" bash "$EXTENSION/scripts/stage_assets.sh" \
    > "$FIXTURE/output" 2>&1
  for artifact in wellen_bridge.js wellen_bridge_bg.wasm LICENSE wellen_bridge_LICENSES.txt; do
    cmp "$TEST_DART_WELLEN/web/pkg/$artifact" "$EXTENSION/web/dart_wellen/$artifact"
  done
  [[ ! -e "$EXTENSION/web/pkg/wellen_bridge_bg.wasm" ]]
  passed=$((passed + 1))
done

mkdir -p "$WORKSPACE/tool/devtools"
cp "$REPO_ROOT/tool/devtools/devtools_dev_mode.sh" "$WORKSPACE/tool/devtools/"
for package in . packages/rohd_hierarchy packages/rohd_waveform \
  packages/rohd_devtools_widgets packages/rohd_source_navigator; do
  mkdir -p "$WORKSPACE/$package"
  printf 'name: fixture\n' > "$WORKSPACE/$package/pubspec.yaml"
done
TEST_REPO_ROOT="$REPO_ROOT" TEST_PATH_WORKSPACE="$WORKSPACE" \
  TEST_PATH_FIXTURE="$FIXTURE" PATH="$FIXTURE/bin:$PATH" python3 - <<'PY'
import json
import os
from pathlib import Path
import subprocess

root = Path(os.environ["TEST_REPO_ROOT"])
workspace = Path(os.environ["TEST_PATH_WORKSPACE"])
fixture = Path(os.environ["TEST_PATH_FIXTURE"])
configuration = json.loads((root / ".vscode/tasks.json").read_text())
tasks = {task["label"]: task for task in configuration["tasks"]}
inputs = {item["id"]: item for item in configuration["inputs"]}
all_task = tasks["Configure Dependency Bundle: All"]
assert all_task["options"]["env"] == {
    "ROHD_GIT_SOURCE": "${input:rohdGitSource}",
    "WAVE_VIEWER_GIT_SOURCE": "${input:waveViewerGitSource}",
    "SCHEMATIC_VIEWER_GIT_SOURCE": "${input:schematicViewerGitSource}",
}
for input_id in [
    "rohdGitSource",
    "waveViewerGitSource",
    "schematicViewerGitSource",
]:
    assert input_id in inputs
for legacy_input_id in [
    "rohdGitRef",
    "waveViewerGitUrl",
    "waveViewerGitRef",
    "schematicViewerGitUrl",
    "schematicViewerGitRef",
]:
    assert legacy_input_id not in inputs
home = fixture / "home"
wave = home / "local viewers/wave"
schematic = home / "local viewers/schematic"
for directory in [wave, wave / "packages/dart_wellen", schematic]:
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "pubspec.yaml").write_text("name: fixture\n")

def run_task(viewer, source, responses="", expected=0):
    title = "Wave" if viewer == "wave" else "Schematic"
    task = tasks[f"Configure Dependency Bundle: {title} Viewer"]
    assert task["options"]["cwd"] == "${workspaceFolder}"
    assert "env" not in task["options"]
    assert task["command"] == (
        "bash tool/devtools/devtools_dev_mode.sh configure-interactive "
        f"{viewer}-viewer ${{input:{viewer}ViewerSource}} && flutter pub get"
    )
    assert f"{viewer}ViewerLocalPath" not in inputs
    assert inputs[f"{viewer}ViewerSource"]["options"] == ["hosted", "git", "local"]
    environment = dict(os.environ, HOME=str(home))
    command = task["command"].replace(
        f"${{input:{viewer}ViewerSource}}", source
    )
    result = subprocess.run(
        ["bash", "-c", command], cwd=workspace, env=environment, input=responses,
        capture_output=True, text=True,
    )
    assert result.returncode == expected, result.stdout + result.stderr
    return result

def run_all(git_sources, expected=0):
    command = all_task["command"].replace(
        "${input:allDependencySource}", "git"
    )
    environment = dict(
        os.environ,
        HOME=str(home),
        ROHD_GIT_SOURCE=git_sources["rohd"],
        WAVE_VIEWER_GIT_SOURCE=git_sources["wave"],
        SCHEMATIC_VIEWER_GIT_SOURCE=git_sources["schematic"],
    )
    result = subprocess.run(
        ["bash", "-c", command],
        cwd=workspace,
        env=environment,
        capture_output=True,
        text=True,
    )
    assert result.returncode == expected, result.stdout + result.stderr
    return result

def state():
    return dict(
        line.split("=", 1)
        for line in (workspace / "rohd_devtools_extension/.devtools_dependency_sources")
        .read_text().splitlines()
    )

run_task("wave", "local", "~/local viewers/wave\n")
assert state()["wave_viewer_local_path"] == str(wave)
assert state()["dart_wellen"] == state()["rohd_wave_viewer"] == "local"
# Selecting a wave path must not require an unused local schematic checkout.
assert state()["rohd_schematic_viewer"] == "hosted"
run_task("schematic", "local", "~/local viewers/schematic\n")
assert state()["schematic_viewer_local_path"] == str(schematic)
assert state()["wave_viewer_local_path"] == str(wave)
run_task("wave", "local", "\n")
assert state()["wave_viewer_local_path"] == str(wave)
overrides = workspace / "rohd_devtools_extension/pubspec_overrides.yaml"
assert f"path: {wave}/packages/dart_wellen" in overrides.read_text()
assert f"path: {schematic}" in overrides.read_text()
before = overrides.read_bytes()
saved = state()
log = Path(os.environ["COMMAND_LOG"])
log.write_text("")
result = run_task("wave", "local", "~/missing viewer\n", expected=1)
assert "Could not find local checkout:" in result.stderr
assert overrides.read_bytes() == before
assert state() == saved
assert log.read_text() == ""
print("4 local viewer task/path checks passed.")

wave_source = "github.com/desmonddak/rohd-wave-viewer:shared-packages-020"
wave_url = "https://github.com/desmonddak/rohd-wave-viewer"
wave_ref = "shared-packages-020"
run_task("wave", "git", f"{wave_source}\n")
assert state()["wave_viewer_git_url"] == wave_url
assert state()["wave_viewer_git_ref"] == wave_ref
assert state()["dart_wellen"] == state()["rohd_wave_viewer"] == "git"
assert overrides.read_text().count(f"url: {wave_url}") == 2
assert overrides.read_text().count(f"ref: {wave_ref}") == 2
assert "path: packages/dart_wellen" in overrides.read_text()
schematic_source = "github.com/example/rohd-schematic-viewer:development"
schematic_url = "https://github.com/example/rohd-schematic-viewer"
run_task("schematic", "git", f"{schematic_source}\n")
assert state()["schematic_viewer_git_url"] == schematic_url
assert state()["wave_viewer_git_url"] == wave_url
assert state()["wave_viewer_git_ref"] == wave_ref
assert overrides.read_text().count(f"url: {wave_url}") == 2
run_task("wave", "git", "\n")
assert state()["wave_viewer_git_url"] == wave_url
assert state()["wave_viewer_git_ref"] == wave_ref
assert f"url: {schematic_url}" in overrides.read_text()
before = overrides.read_bytes()
saved = state()
result = run_task("wave", "git", "github.com/example/rohd-wave-viewer\n", expected=2)
assert "must use the format repository:ref" in result.stderr
assert overrides.read_bytes() == before
assert state() == saved
print("3 Git viewer task/source persistence checks passed.")

all_sources = {
    "rohd": "github.com/example/rohd:release-candidate",
    "wave": "github.com/example/rohd-wave-viewer:feature/wave",
    "schematic": "github.com/example/rohd-schematic-viewer:feature/schematic",
}
run_all(all_sources)
assert state()["rohd_git_url"] == "https://github.com/example/rohd"
assert state()["rohd_git_ref"] == "release-candidate"
assert state()["wave_viewer_git_url"] == "https://github.com/example/rohd-wave-viewer"
assert state()["wave_viewer_git_ref"] == "feature/wave"
assert state()["schematic_viewer_git_url"] == "https://github.com/example/rohd-schematic-viewer"
assert state()["schematic_viewer_git_ref"] == "feature/schematic"
before = overrides.read_bytes()
saved = state()
invalid_sources = dict(all_sources, wave="github.com/example/rohd-wave-viewer")
result = run_all(invalid_sources, expected=2)
assert "must use the format repository:ref" in result.stderr
assert overrides.read_bytes() == before
assert state() == saved
print("2 combined Git source task checks passed.")

run_task("wave", "hosted")
run_task("schematic", "hosted")
assert state()["dart_wellen"] == state()["rohd_wave_viewer"] == "hosted"
assert state()["rohd_schematic_viewer"] == "hosted"
print("2 hosted viewer task/source checks passed.")
PY
passed=$((passed + 11))

echo "$passed DevTools workspace checks passed."
