#!/bin/bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# Test the existing Pana runner with fake SDKs and no network access.
# Usage: bash tool/test/pana_source_test.sh

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
export SOURCE="$FIXTURE/source package" SDK_LOG="$FIXTURE/sdk.log"
export NAVIGATOR="$FIXTURE/rohd_source_navigator"
export PUB_CACHE="$FIXTURE/pub cache" TMPDIR="$FIXTURE/temp space"
export FLUTTER_ROOT="$FIXTURE/flutter sdk" PANA_ANALYSIS_INCLUDES=1

mkdir -p "$SOURCE/lib" "$SOURCE/.dart_tool" "$SOURCE/example" \
  "$FIXTURE/bin" "$PUB_CACHE/bin" "$TMPDIR" "$FLUTTER_ROOT/bin"
for executable in bash cmp dirname grep mkdir mktemp readlink rm tar; do
  ln -s "$(command -v "$executable")" "$FIXTURE/bin/$executable"
done
printf 'name: fixture\n' > "$SOURCE/pubspec.yaml"
printf 'library fixture;\n' > "$SOURCE/lib/fixture.dart"
for file in pubspec.lock pubspec_overrides.yaml analysis_options.yaml \
  .dart_tool/package_config.json example/pubspec.lock example/pubspec_overrides.yaml; do
  printf 'checkout-only state\n' > "$SOURCE/$file"
done
cp -R "$SOURCE" "$FIXTURE/original"
cp -R "$SOURCE" "$NAVIGATOR"
cp -R "$NAVIGATOR" "$FIXTURE/original-navigator"

cat > "$FIXTURE/bin/dart" <<'EOF'
#!/bin/bash
set -euo pipefail
[[ "$PWD" == "$TMPDIR"/rohd-pana.*/package ]]
printf '%s|%s\n' "${0##*/}" "$*" >> "$SDK_LOG"
case "$*" in
  'pub get')
    for file in pubspec.lock pubspec_overrides.yaml analysis_options.yaml \
      .dart_tool example/pubspec.lock example/pubspec_overrides.yaml; do
      [[ ! -e "$file" ]]
    done
    cmp pubspec.yaml "$SOURCE/pubspec.yaml"
    cmp lib/fixture.dart "$SOURCE/lib/fixture.dart"
    printf 'hosted resolution\n' > pubspec.lock ;;
  'pub downgrade') printf 'downgraded resolution\n' > pubspec.lock ;;
  'analyze --fatal-infos lib'|'analyze --fatal-infos --no-pub lib')
    if [[ "${FAIL_COMMAND:-}" == downgrade-analysis ]] &&
      grep -q downgraded pubspec.lock; then
      exit 71
    fi ;;
  *) exit 99 ;;
esac
if [[ "${FAIL_COMMAND:-}" == "$*" ]]; then exit 71; fi
EOF
chmod +x "$FIXTURE/bin/dart"
ln -s "$FIXTURE/bin/dart" "$FLUTTER_ROOT/bin/flutter"
ln -s "$FLUTTER_ROOT/bin/flutter" "$FIXTURE/bin/flutter"

cat > "$PUB_CACHE/bin/pana" <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ "$PWD" == "$SOURCE" ]]; then
  [[ "$*" == '--exit-code-threshold 0 .' ]]
else
  [[ "$PWD" == "$TMPDIR"/rohd-pana.*/package && "$PANA_ANALYSIS_INCLUDES" == 0 ]]
  if [[ "$EXPECTED_SDK" == flutter ]]; then
    [[ $# -eq 5 && "$1" == --exit-code-threshold && "$2" == "$EXPECTED_THRESHOLD" &&
      "$3" == --flutter-sdk && "$4" == "$EXPECTED_FLUTTER_ROOT" && "$5" == . ]]
  else
    [[ $# -eq 3 && "$1" == --exit-code-threshold && "$2" == "$EXPECTED_THRESHOLD" &&
      "$3" == . ]]
  fi
  printf 'changed by Pana\n' > pubspec.yaml
fi
printf 'pana\n' >> "$SDK_LOG"
exit "${PANA_STATUS:-0}"
EOF
chmod +x "$PUB_CACHE/bin/pana"
export EXPECTED_FLUTTER_ROOT="$FLUTTER_ROOT"
export EXPECTED_THRESHOLD=0
cd "$SOURCE"

passed=0
run_case() {
  local expected="$1" status=0
  shift
  : > "$SDK_LOG"
  PATH="$FIXTURE/bin" /bin/bash "$REPO_ROOT/tool/gh_actions/pana_source.sh" \
    "$@" > "$FIXTURE/output" 2>&1 || status=$?
  if [[ "$status" -ne "$expected" ]]; then
    cat "$FIXTURE/output"
    echo "Expected exit $expected, got $status for: $*" >&2
    exit 1
  fi
  diff -ru "$FIXTURE/original" "$SOURCE"
  diff -ru "$FIXTURE/original-navigator" "$NAVIGATOR"
  [[ -z "$(find "$TMPDIR" -mindepth 1 -print -quit)" ]]
  passed=$((passed + 1))
}

run_case 0
[[ "$(cat "$SDK_LOG")" == pana ]]
PANA_STATUS=127 run_case 127
run_case 2 "$SOURCE"
run_case 2 "$SOURCE" invalid
run_case 2 "$FIXTURE/missing" dart

for sdk in dart flutter; do
  export EXPECTED_SDK="$sdk"
  export EXPECTED_THRESHOLD=0
  analyze='analyze --fatal-infos'
  if [[ "$sdk" == flutter ]]; then analyze+=' --no-pub'; fi
  analyze+=' lib'
  run_case 0 "$SOURCE" "$sdk"
  expected_log="$(printf '%s|%s\n' "$sdk" 'pub get' "$sdk" "$analyze" \
    "$sdk" 'pub downgrade' "$sdk" "$analyze"; printf 'pana\n')"
  [[ "$(cat "$SDK_LOG")" == "$expected_log" ]]
  PANA_STATUS=73 run_case 73 "$SOURCE" "$sdk"
  for failure in 'pub get' "$analyze" 'pub downgrade' downgrade-analysis; do
    FAIL_COMMAND="$failure" run_case 71 "$SOURCE" "$sdk"
    ! grep -q '^pana$' "$SDK_LOG"
  done
done

export EXPECTED_SDK=dart EXPECTED_THRESHOLD=10
run_case 0 "$NAVIGATOR" dart
[[ "$(cat "$SDK_LOG")" == $'dart|pub get\ndart|analyze --fatal-infos lib\ndart|pub downgrade\ndart|analyze --fatal-infos lib\npana' ]]

mv "$PUB_CACHE/bin/pana" "$FIXTURE/pana"
export EXPECTED_THRESHOLD=0
run_case 2 "$SOURCE" dart
grep -q 'Pana is required' "$FIXTURE/output"
[[ ! -s "$SDK_LOG" ]]
mv "$FIXTURE/pana" "$PUB_CACHE/bin/pana"
printf 'dependency_overrides:\n' >> "$SOURCE/pubspec.yaml"
cp "$SOURCE/pubspec.yaml" "$FIXTURE/original/pubspec.yaml"
run_case 2 "$SOURCE" dart
grep -q 'Move inline dependency overrides' "$FIXTURE/output"
[[ ! -s "$SDK_LOG" ]]

echo "$passed Pana runner checks passed using only fake SDK/Pana executables."
