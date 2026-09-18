#!/bin/bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# prepare_release_test.sh
# Test preparation defaults, versions, guards, and selected-package checks.
# Uses disposable local Git repositories and stubbed check/publication commands.
# Only the metadata helper runs on real Dart, using root package dependencies;
# commits and artifact installation are confined to temporary test repositories.
#
# Usage (after installing the root package's dependencies):
#   bash tool/test/prepare_release_test.sh
#
# 2026 September 18
# Author: Max Korbel <max.korbel@intel.com>

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly FIXTURE="$(mktemp -d)"
readonly UPSTREAM="$FIXTURE/upstream"
readonly RELEASE="$FIXTURE/release"
trap 'rm -rf "$FIXTURE"' EXIT

export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_ALLOW_PROTOCOL=file
export GIT_AUTHOR_NAME='Release Test' GIT_AUTHOR_EMAIL='release-test@example.invalid'
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
export SDK_LOG="$FIXTURE/sdk.log" STAGE_LOG="$FIXTURE/stages.log"
export REAL_DART="$(command -v dart)" PACKAGE_CONFIG="$REPO_ROOT/.dart_tool/package_config.json"
if [[ -x "$(dirname "$REAL_DART")/cache/dart-sdk/bin/dart" ]]; then
  REAL_DART="$(dirname "$REAL_DART")/cache/dart-sdk/bin/dart"
fi
export METADATA_SCRIPT="$RELEASE/tool/prepare_release_metadata.dart"

mkdir -p "$FIXTURE/bin" "$UPSTREAM/tool/gh_actions/devtool" \
  "$UPSTREAM/lib/src/utilities" "$UPSTREAM/extension/devtools"
for executable in bash cat cp dirname find git grep mkdir mktemp rm sed tar; do
  ln -s "$(command -v "$executable")" "$FIXTURE/bin/$executable"
done
printf '%s\n' \
  '#!/bin/bash' \
  'if [[ "$#" -ge 2 && "$1" == run && "$2" == "$METADATA_SCRIPT" ]]; then' \
  '  shift' \
  '  exec "$REAL_DART" "--packages=$PACKAGE_CONFIG" "$@"' \
  'fi' \
  'printf "%s|%s|%s\n" "${0##*/}" "$PWD" "$*" >> "$SDK_LOG"' \
  'case "$*" in' \
  '  "pub publish --dry-run") printf "dry-run\n" >> "$STAGE_LOG" ;;' \
  '  "pub get"|"format --output=none --set-exit-if-changed ."|"analyze --fatal-infos"|"test")' \
  '    if [[ "${FAIL_PACKAGE:-}" == "${PWD##*/}" && "${FAIL_COMMAND:-}" == "$*" ]]; then' \
  '      echo "Simulated check failure: $*" >&2' \
  '      exit 71' \
  '    fi ;;' \
  '  *) exit 99 ;;' \
  'esac' > "$FIXTURE/bin/dart"
chmod +x "$FIXTURE/bin/dart"
ln -s dart "$FIXTURE/bin/flutter"

cp "$REPO_ROOT/tool/prepare_release.sh" "$REPO_ROOT/tool/check_release.sh" \
  "$REPO_ROOT/tool/prepare_release_metadata.dart" "$UPSTREAM/tool/"
cp "$REPO_ROOT/tool/gh_actions/check_tmp_test.sh" "$UPSTREAM/tool/gh_actions/"
printf '%s\n' '#!/bin/bash' \
  '[[ -f "$1/build/index.html" && -f "$1/config.yaml" ]] || exit 1' \
  'printf "smoke\n" >> "$STAGE_LOG"' \
  'exit "${SMOKE_STATUS:-0}"' > "$UPSTREAM/tool/gh_actions/devtool/test_devtools_install.sh"
printf '%s\n' '#!/bin/bash' 'printf "checks\n" >> "$STAGE_LOG"' \
  'exit "${ROOT_CHECK_STATUS:-0}"' > "$UPSTREAM/tool/run_checks.sh"
chmod +x "$UPSTREAM/tool/gh_actions/check_tmp_test.sh" \
  "$UPSTREAM/tool/gh_actions/devtool/test_devtools_install.sh" "$UPSTREAM/tool/run_checks.sh"
printf "version: '0.6.11' # release\n" > "$UPSTREAM/pubspec.yaml"
printf "static const String version = '0.0.0';\n" > "$UPSTREAM/lib/src/utilities/config.dart"
printf '## Next Release\n' > "$UPSTREAM/CHANGELOG.md"
printf 'fixture configuration\n' > "$UPSTREAM/extension/devtools/config.yaml"
printf 'extension/devtools/build/\n' > "$UPSTREAM/.gitignore"
for package in rohd_hierarchy rohd_waveform rohd_devtools_widgets; do
  mkdir -p "$UPSTREAM/packages/$package"
  printf '## Next Release\n' > "$UPSTREAM/packages/$package/CHANGELOG.md"
done
printf 'version: 1.2.3\n' > "$UPSTREAM/packages/rohd_hierarchy/pubspec.yaml"
printf 'version: 2.3.4\n' > "$UPSTREAM/packages/rohd_waveform/pubspec.yaml"
printf 'version: 3.4.5\n' > "$UPSTREAM/packages/rohd_devtools_widgets/pubspec.yaml"

git init --quiet --initial-branch=main "$UPSTREAM"
git -C "$UPSTREAM" add .
git -C "$UPSTREAM" commit --quiet -m 'Fixture main'

build_artifact() {
  git -C "$UPSTREAM" checkout --quiet --detach main
  mkdir -p "$UPSTREAM/extension/devtools/build"
  printf 'artifact payload\n' > "$UPSTREAM/extension/devtools/build/index.html"
  git -C "$UPSTREAM" add -f extension/devtools/build/index.html
  git -C "$UPSTREAM" commit --quiet -m 'Fixture artifact'
  git -C "$UPSTREAM" branch --force artifacts HEAD
  git -C "$UPSTREAM" checkout --quiet main
}

build_artifact
git clone --quiet --branch main "$UPSTREAM" "$RELEASE"
git -C "$RELEASE" checkout --quiet -b preparation
git -C "$RELEASE" commit --quiet --allow-empty -m 'Fixture release preparation'
mkdir -p "$RELEASE/extension/devtools/build"
printf 'original payload\n' > "$RELEASE/extension/devtools/build/index.html"

passed=0
run_case() {
  local expected="$1"
  local message="$2"
  shift 2
  local status=0
  : > "$SDK_LOG"
  : > "$STAGE_LOG"
  PATH="$FIXTURE/bin" ROHD_ARTIFACT_REPOSITORY="$UPSTREAM" ROHD_ARTIFACT_BRANCH=artifacts \
    /bin/bash "$RELEASE/tool/prepare_release.sh" "$@" > "$FIXTURE/output" 2>&1 || status=$?
  if [[ "$status" -ne "$expected" ]] || ! grep -Fq "$message" "$FIXTURE/output"; then
    cat "$FIXTURE/output"
    echo "Expected exit $expected and '$message', got exit $status." >&2
    exit 1
  fi
  passed=$((passed + 1))
}

assert_unchanged() {
  [[ ! -s "$SDK_LOG" ]]
  [[ "$(cat "$RELEASE/pubspec.yaml")" == "version: '0.6.11' # release" ]]
  [[ "$(cat "$RELEASE/lib/src/utilities/config.dart")" == "static const String version = '0.0.0';" ]]
  [[ "$(cat "$RELEASE/CHANGELOG.md")" == '## Next Release' ]]
  [[ "$(cat "$RELEASE/extension/devtools/build/index.html")" == 'original payload' ]]
  [[ "$(cat "$RELEASE/extension/devtools/config.yaml")" == 'fixture configuration' ]]
  for package in rohd_hierarchy rohd_waveform rohd_devtools_widgets; do
    [[ "$(cat "$RELEASE/packages/$package/CHANGELOG.md")" == '## Next Release' ]]
  done
}

expected_checks() {
  local package="$1"
  local sdk=dart
  if [[ "$package" == rohd_devtools_widgets ]]; then
    sdk=flutter
  fi
  printf '%s|%s|%s\n' "$sdk" "$RELEASE/packages/$package" 'pub get'
  printf '%s|%s|%s\n' dart "$RELEASE/packages/$package" 'format --output=none --set-exit-if-changed .'
  printf '%s|%s|%s\n' "$sdk" "$RELEASE/packages/$package" 'analyze --fatal-infos'
  printf '%s|%s|%s\n' "$sdk" "$RELEASE/packages/$package" test
}

git -C "$UPSTREAM" commit --quiet --allow-empty -m 'Fixture main advances'
readonly MAIN_COMMIT="$(git -C "$UPSTREAM" rev-parse main)"
run_case 1 'The release branch does not contain the latest upstream main.'
assert_unchanged
[[ ! -s "$STAGE_LOG" ]]

git -C "$RELEASE" merge --quiet --no-edit "$MAIN_COMMIT"
run_case 1 'The DevTools artifact is stale.'
assert_unchanged
[[ ! -s "$STAGE_LOG" ]]

build_artifact
export SMOKE_STATUS=42
run_case 42 'Fetching the ROHD DevTools build'
assert_unchanged
[[ "$(cat "$STAGE_LOG")" == smoke ]]
unset SMOKE_STATUS

run_case 0 "DevTools source commit (upstream main): $MAIN_COMMIT"
[[ "$(cat "$STAGE_LOG")" == $'smoke\nchecks\ndry-run\ndry-run\ndry-run\ndry-run' ]]
expected_log="$(
  for package in rohd_hierarchy rohd_waveform rohd_devtools_widgets; do
    expected_checks "$package"
  done
  printf 'dart|%s|pub publish --dry-run\n' "$RELEASE"
  printf 'dart|%s|pub publish --dry-run\n' "$RELEASE/packages/rohd_hierarchy"
  printf 'dart|%s|pub publish --dry-run\n' "$RELEASE/packages/rohd_waveform"
  printf 'flutter|%s|pub publish --dry-run\n' "$RELEASE/packages/rohd_devtools_widgets"
)"
[[ "$(cat "$SDK_LOG")" == "$expected_log" ]]
[[ "$(cat "$RELEASE/pubspec.yaml")" == "version: '0.6.11' # release" ]]
[[ "$(cat "$RELEASE/lib/src/utilities/config.dart")" == "static const String version = '0.6.11';" ]]
[[ "$(cat "$RELEASE/CHANGELOG.md")" == '## 0.6.11' ]]
[[ "$(cat "$RELEASE/extension/devtools/build/index.html")" == 'artifact payload' ]]
[[ "$(git -C "$RELEASE" rev-parse HEAD)" != "$MAIN_COMMIT" ]]
[[ "$(cat "$RELEASE/packages/rohd_hierarchy/CHANGELOG.md")" == '## 1.2.3' ]]
[[ "$(cat "$RELEASE/packages/rohd_waveform/CHANGELOG.md")" == '## 2.3.4' ]]
[[ "$(cat "$RELEASE/packages/rohd_devtools_widgets/CHANGELOG.md")" == '## 3.4.5' ]]
git -C "$RELEASE" diff --exit-code -- pubspec.yaml 'packages/*/pubspec.yaml'

run_case 0 "DevTools source commit (upstream main): $MAIN_COMMIT" rohd
[[ "$(cat "$SDK_LOG")" == "dart|$RELEASE|pub publish --dry-run" ]]

export ROOT_CHECK_STATUS=72
run_case 72 '=== rohd: project checks ==='
[[ ! -s "$SDK_LOG" ]]
[[ "$(cat "$STAGE_LOG")" == $'smoke\nchecks' ]]
unset ROOT_CHECK_STATUS

git -C "$UPSTREAM" update-ref -d refs/heads/artifacts
printf "static const String version = '0.0.0';\n" > "$RELEASE/lib/src/utilities/config.dart"
printf '## Next Release\n' > "$RELEASE/CHANGELOG.md"
run_case 0 'rohd_hierarchy: 1.2.3 (prepared from pubspec.yaml)' rohd_hierarchy rohd_waveform
[[ "$(cat "$STAGE_LOG")" == $'dry-run\ndry-run' ]]
[[ "$(cat "$RELEASE/lib/src/utilities/config.dart")" == "static const String version = '0.0.0';" ]]
[[ "$(cat "$RELEASE/CHANGELOG.md")" == '## Next Release' ]]
expected_log="$(
  expected_checks rohd_hierarchy
  expected_checks rohd_waveform
  printf 'dart|%s|pub publish --dry-run\n' "$RELEASE/packages/rohd_hierarchy"
  printf 'dart|%s|pub publish --dry-run\n' "$RELEASE/packages/rohd_waveform"
)"
[[ "$(cat "$SDK_LOG")" == "$expected_log" ]]

run_case 0 'rohd_devtools_widgets: PASSED' rohd_devtools_widgets
expected_log="$(
  expected_checks rohd_devtools_widgets
  printf 'flutter|%s|pub publish --dry-run\n' "$RELEASE/packages/rohd_devtools_widgets"
)"
[[ "$(cat "$SDK_LOG")" == "$expected_log" ]]
[[ "$(cat "$STAGE_LOG")" == 'dry-run' ]]

for package in rohd_hierarchy rohd_waveform rohd_devtools_widgets; do
  for check_command in 'pub get' 'format --output=none --set-exit-if-changed .' 'analyze --fatal-infos' test; do
    export FAIL_PACKAGE="$package" FAIL_COMMAND="$check_command"
    run_case 71 "Simulated check failure: $check_command" "$package" rohd_hierarchy rohd_waveform
    [[ ! -s "$STAGE_LOG" ]]
    expected_log="$(
      while IFS= read -r expected_line; do
        printf '%s\n' "$expected_line"
        if [[ "$expected_line" == *"|$check_command" ]]; then
          break
        fi
      done < <(expected_checks "$package")
    )"
    [[ "$(cat "$SDK_LOG")" == "$expected_log" ]]
  done
done
unset FAIL_PACKAGE FAIL_COMMAND

printf 'name: rohd_hierarchy\n' > "$RELEASE/packages/rohd_hierarchy/pubspec.yaml"
run_case 2 'needs a stable major.minor.patch version.' rohd_hierarchy
[[ ! -s "$STAGE_LOG" && ! -s "$SDK_LOG" ]]
run_case 0 'Usage:' --help
[[ ! -s "$STAGE_LOG" && ! -s "$SDK_LOG" ]]

echo "$passed preparation checks passed using local Git fixtures and stubbed package/publication commands."