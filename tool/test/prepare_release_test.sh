#!/bin/bash

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

mkdir -p "$FIXTURE/bin" "$UPSTREAM/tool/gh_actions/devtool" \
  "$UPSTREAM/lib/src/utilities" "$UPSTREAM/extension/devtools"
for executable in bash cat cp dirname git grep mkdir mktemp rm sed tar; do
  ln -s "$(command -v "$executable")" "$FIXTURE/bin/$executable"
done
printf '%s\n' \
  '#!/bin/bash' \
  'printf "%s|%s\n" "$PWD" "$*" >> "$SDK_LOG"' \
  '[[ "$#" -eq 3 && "$1" == pub && "$2" == publish && "$3" == --dry-run ]] || exit 99' \
  'printf "dry-run\n" >> "$STAGE_LOG"' > "$FIXTURE/bin/dart"
chmod +x "$FIXTURE/bin/dart"

cp "$REPO_ROOT/tool/prepare_release.sh" "$REPO_ROOT/tool/check_release.sh" "$UPSTREAM/tool/"
printf '%s\n' '#!/bin/bash' 'exit 0' > "$UPSTREAM/tool/gh_actions/check_tmp_test.sh"
printf '%s\n' '#!/bin/bash' \
  '[[ -f "$1/build/index.html" && -f "$1/config.yaml" ]] || exit 1' \
  'printf "smoke\n" >> "$STAGE_LOG"' \
  'exit "${SMOKE_STATUS:-0}"' > "$UPSTREAM/tool/gh_actions/devtool/test_devtools_install.sh"
printf '%s\n' '#!/bin/bash' 'printf "checks\n" >> "$STAGE_LOG"' > "$UPSTREAM/tool/run_checks.sh"
chmod +x "$UPSTREAM/tool/gh_actions/check_tmp_test.sh" \
  "$UPSTREAM/tool/gh_actions/devtool/test_devtools_install.sh" "$UPSTREAM/tool/run_checks.sh"
printf 'version: 0.0.0\n' > "$UPSTREAM/pubspec.yaml"
printf "static const String version = '0.0.0';\n" > "$UPSTREAM/lib/src/utilities/config.dart"
printf '## Next Release\n' > "$UPSTREAM/CHANGELOG.md"
printf 'fixture configuration\n' > "$UPSTREAM/extension/devtools/config.yaml"
printf 'extension/devtools/build/\n' > "$UPSTREAM/.gitignore"

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
  local status=0
  : > "$SDK_LOG"
  : > "$STAGE_LOG"
  PATH="$FIXTURE/bin" ROHD_ARTIFACT_REPOSITORY="$UPSTREAM" ROHD_ARTIFACT_BRANCH=artifacts \
    /bin/bash "$RELEASE/tool/prepare_release.sh" 0.6.11 > "$FIXTURE/output" 2>&1 || status=$?
  if [[ "$status" -ne "$expected" ]] || ! grep -Fq "$message" "$FIXTURE/output"; then
    cat "$FIXTURE/output"
    echo "Expected exit $expected and '$message', got exit $status." >&2
    exit 1
  fi
  passed=$((passed + 1))
}

assert_unchanged() {
  [[ ! -s "$SDK_LOG" ]]
  [[ "$(cat "$RELEASE/pubspec.yaml")" == 'version: 0.0.0' ]]
  [[ "$(cat "$RELEASE/lib/src/utilities/config.dart")" == "static const String version = '0.0.0';" ]]
  [[ "$(cat "$RELEASE/CHANGELOG.md")" == '## Next Release' ]]
  [[ "$(cat "$RELEASE/extension/devtools/build/index.html")" == 'original payload' ]]
  [[ "$(cat "$RELEASE/extension/devtools/config.yaml")" == 'fixture configuration' ]]
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
[[ "$(cat "$STAGE_LOG")" == $'smoke\nchecks\ndry-run' ]]
[[ "$(cat "$SDK_LOG")" == "$RELEASE|pub publish --dry-run" ]]
[[ "$(cat "$RELEASE/pubspec.yaml")" == 'version: 0.6.11' ]]
[[ "$(cat "$RELEASE/lib/src/utilities/config.dart")" == "static const String version = '0.6.11';" ]]
[[ "$(cat "$RELEASE/CHANGELOG.md")" == '## 0.6.11' ]]
[[ "$(cat "$RELEASE/extension/devtools/build/index.html")" == 'artifact payload' ]]
[[ "$(git -C "$RELEASE" rev-parse HEAD)" != "$MAIN_COMMIT" ]]

echo "$passed preparation checks passed using local Git fixtures and fake SDK executables."