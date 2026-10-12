#!/bin/bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# prepare_release.sh
# Prepare selected ROHD packages for release without publishing them.
#
# Usage (from repo root):
#   tool/prepare_release.sh [--run-tests] [package ...]
#
# Run on your preparation branch after merging or rebasing the latest intel/rohd
# main into it. When selecting ROHD, wait for that main commit's DevTools build.
# Publish from the preparation branch; merge its PR after publication succeeds.
#
# With no arguments, select rohd, rohd_hierarchy, rohd_waveform,
# rohd_devtools_widgets, and rohd_source_navigator.
# Explicit package names select only those packages.
# Set each selected package's version in its own pubspec.yaml before running.
# The manifests are never rewritten; each pending changelog heading is promoted
# to its package's version (an existing version heading is also accepted).
#
# Selecting ROHD also synchronizes Config.version, fetches and verifies artifacts,
# smoke-tests and installs the DevTools build, and runs tool/run_checks.sh with
# --skip-tests by default. It also compiles and packages a temporary VSIX using
# the release workflow's helper. The smoke test and VSIX check always run.
# The DevTools build comes from main, not from branch-only implementation changes.
# Each selected sub-package gets dependency resolution, a non-writing format check,
# and analysis (including fatal infos) in its own directory. Dart is used
# for hierarchy/waveform/source navigator, Flutter for widgets, and dart format
# for all sub-packages. Test suites and the isolated hosted Pana score gate are
# skipped by default; verify CI results for the release commit. Add --run-tests
# to also run all selected package suites locally, including ROHD's simulator
# prerequisites when ROHD is selected. Add --run-pana to run hosted dependency
# resolution, pub downgrade, library analysis, and the Pana score gate.
# Only after all selected checks pass do publication dry runs start.
# It never publishes, commits, tags, pushes, merges, or rebases.
#
# Dart is required to read YAML metadata using the root package's dependencies.
# Selecting ROHD also requires Node.js and npm (release CI uses Node.js 24).
# Selecting rohd_devtools_widgets also requires Flutter. --run-pana requires
# Pana (tool/gh_actions/install_pana.sh) and hosted dependencies.
# Any failed prerequisite or package check stops preparation before dry runs.
#
# Examples:
#
#   ROHD plus all four publishable sub-packages (the default):
#     tool/prepare_release.sh
#
#   All five packages, including their test suites:
#     tool/prepare_release.sh --run-tests
#
#   ROHD only:
#     tool/prepare_release.sh rohd
#
#   ROHD only, including its test suite:
#     tool/prepare_release.sh --run-tests rohd
#
#   ROHD plus hierarchy and waveform:
#     tool/prepare_release.sh rohd rohd_hierarchy rohd_waveform
#
#   Only hierarchy and waveform (no ROHD metadata or DevTools changes):
#     tool/prepare_release.sh rohd_hierarchy rohd_waveform
#
#   Only source navigator:
#     tool/prepare_release.sh rohd_source_navigator
#
#   Sub-package archive checks only (no metadata preparation):
#     tool/check_release.sh rohd_hierarchy rohd_waveform rohd_devtools_widgets
#
# All publication checks above use --dry-run. Review warnings and archive contents;
# local dependency overrides do not prove hosted dependencies work for consumers.
# See doc/releases.md for prerequisites, publication order, and manual release steps.
#
# 2026 July 30
# Author: Max Korbel <max.korbel@intel.com>

set -euo pipefail

export DASH__SUPPRESS_ANALYTICS=true
export FLUTTER_SUPPRESS_ANALYTICS=true

if [[ $# -eq 1 && "$1" == '--help' ]]; then
  echo "Usage: $0 [--run-tests] [--run-pana] [package ...]"
  echo "Packages: rohd rohd_hierarchy rohd_waveform rohd_devtools_widgets rohd_source_navigator"
  echo "Defaults to all five packages, using each package's pubspec.yaml version."
  echo "Test suites are skipped by default; use --run-tests to include them."
  echo "Pana score checks are skipped by default; use --run-pana to include them."
  echo "Artifact verification and its smoke test still run when ROHD is selected."
  echo "Selecting ROHD also checks VSIX packaging (requires Node.js and npm)."
  echo "Prepares metadata, runs package checks and publication dry runs; never uploads packages."
  exit 0
fi
run_tests=false
run_pana=false
packages=()
for argument in "$@"; do
  if [[ "$argument" == '--run-tests' ]]; then
    run_tests=true
  elif [[ "$argument" == '--run-pana' ]]; then
    run_pana=true
  else
    packages+=("$argument")
  fi
done
set -- "${packages[@]}"
if [[ $# -eq 0 ]]; then
  set -- rohd rohd_hierarchy rohd_waveform rohd_devtools_widgets rohd_source_navigator
fi

# Resolve all paths and source provenance before changing the working tree.
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
bash "$SCRIPT_DIR/check_release.sh" --validate-only "$@"
if [[ "$run_tests" == true ]]; then
  echo "Test suites enabled for selected packages (--run-tests)."
else
  echo "Test suites skipped; verify CI results for the release commit. Use --run-tests to run them locally."
fi
if [[ "$run_pana" == true ]]; then
  echo "Pana score checks enabled for selected sub-packages (--run-pana)."
else
  echo "Pana score checks skipped; verify CI results for the release commit. Use --run-pana to run them locally."
fi
prepare_rohd=false
for package in "$@"; do
  if [[ "$package" == rohd ]]; then
    prepare_rohd=true
  elif [[ "$run_pana" == true ]] &&
      ! PATH="$PATH:${PUB_CACHE:-$HOME/.pub-cache}/bin" command -v pana > /dev/null; then
    echo "Pana is required; run tool/gh_actions/install_pana.sh first." >&2
    exit 2
  fi
done
cd "$REPO_ROOT"
dart run "$SCRIPT_DIR/prepare_release_metadata.dart" --check "$@"
readonly ARTIFACT_REPOSITORY="${ROHD_ARTIFACT_REPOSITORY:-https://github.com/intel/rohd.git}"
readonly ARTIFACT_BRANCH="${ROHD_ARTIFACT_BRANCH:-artifacts}"
readonly SOURCE_COMMIT="$(git -C "$REPO_ROOT" rev-parse HEAD)"
readonly TEMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

cd "$REPO_ROOT"

# Fail before making release changes if earlier tests left temporary outputs.
if [[ "$prepare_rohd" == true ]]; then
  tool/gh_actions/check_tmp_test.sh
fi

echo "Fetching main from $ARTIFACT_REPOSITORY..."
git fetch --quiet --no-tags "$ARTIFACT_REPOSITORY" refs/heads/main
readonly MAIN_COMMIT="$(git rev-parse FETCH_HEAD)"

if ! git merge-base --is-ancestor "$MAIN_COMMIT" "$SOURCE_COMMIT"; then
  echo "The release branch does not contain the latest upstream main." >&2
  echo "  Release source: $SOURCE_COMMIT" >&2
  echo "  Upstream main:  $MAIN_COMMIT" >&2
  echo "Merge or rebase onto the latest main, then rerun preparation." >&2
  exit 1
fi

if [[ "$prepare_rohd" == true ]]; then
  echo "Fetching the ROHD DevTools build from $ARTIFACT_REPOSITORY ($ARTIFACT_BRANCH)..."
  git fetch --quiet --no-tags "$ARTIFACT_REPOSITORY" "refs/heads/$ARTIFACT_BRANCH"
  readonly ARTIFACT_COMMIT="$(git rev-parse FETCH_HEAD)"
  readonly ARTIFACT_SOURCE_COMMIT="$(git rev-parse "$ARTIFACT_COMMIT^")"

  if [[ "$ARTIFACT_SOURCE_COMMIT" != "$MAIN_COMMIT" ]]; then
    echo "The DevTools artifact is stale." >&2
    echo "  Upstream main:   $MAIN_COMMIT" >&2
    echo "  Artifact source: $ARTIFACT_SOURCE_COMMIT" >&2
    echo "Wait for the artifact workflow for upstream main to finish, then rerun preparation." >&2
    exit 1
  fi

  # Extract into a temporary directory and smoke-test before replacing the local
  # release payload, leaving the existing build intact if validation fails.
  git cat-file -e "$ARTIFACT_COMMIT:extension/devtools/build/index.html"
  git cat-file -e "$ARTIFACT_COMMIT:extension/devtools/config.yaml"
  git archive "$ARTIFACT_COMMIT" extension/devtools | tar -x -C "$TEMP_DIR"

  tool/gh_actions/devtool/test_devtools_install.sh \
    "$TEMP_DIR/extension/devtools"

  # Install the tested artifact. The web build is ignored by Git but included in
  # the published package through the exception in .pubignore.
  rm -rf extension/devtools/build
  mkdir -p extension/devtools
  cp -R "$TEMP_DIR/extension/devtools/build" extension/devtools/build
  cp "$TEMP_DIR/extension/devtools/config.yaml" extension/devtools/config.yaml
fi

dart run "$SCRIPT_DIR/prepare_release_metadata.dart" "$@"

# Run the same checks used for normal development and reject malformed diffs.
# Publishing remains a separate, intentionally manual operation.
if [[ "$prepare_rohd" == true ]]; then
  echo "=== rohd: project checks ==="
  if [[ "$run_tests" == true ]]; then
    tool/run_checks.sh
  else
    tool/run_checks.sh --skip-tests
  fi
  echo "=== rohd: VS Code extension packaging check ==="
  bash "$SCRIPT_DIR/package_vscode.sh" "$TEMP_DIR/rohd-vscode.vsix"
fi
for package in "$@"; do
  if [[ "$package" == rohd ]]; then
    continue
  fi
  sdk=dart
  if [[ "$package" == rohd_devtools_widgets ]]; then
    sdk=flutter
  fi
  (
    cd "$REPO_ROOT/packages/$package"
    echo "=== $package: resolve dependencies ($sdk pub get) ==="
    "$sdk" pub get
    echo "=== $package: verify formatting ==="
    dart format --output=none --set-exit-if-changed .
    echo "=== $package: analyze ($sdk analyze --fatal-infos) ==="
    "$sdk" analyze --fatal-infos
    if [[ "$run_tests" == true ]]; then
      echo "=== $package: tests ($sdk test) ==="
      "$sdk" test
    else
      echo "=== $package: tests skipped (use --run-tests) ==="
    fi
  )
  if [[ "$run_pana" == true ]]; then
    bash "$SCRIPT_DIR/gh_actions/pana_source.sh" "$REPO_ROOT/packages/$package" "$sdk"
  else
    echo "=== $package: Pana score gate skipped (use --run-pana) ==="
  fi
done
git diff --check
bash "$SCRIPT_DIR/check_release.sh" "$@"

echo "Selected packages prepared from source commit $SOURCE_COMMIT."
if [[ "$prepare_rohd" == true ]]; then
  echo "DevTools source commit (upstream main): $MAIN_COMMIT"
  echo "DevTools artifact commit: $ARTIFACT_COMMIT"
  echo "VSIX build check passed; its temporary archive is discarded, not published."
fi

cat <<EOF

Review the changelog and working tree before performing the manual publish step.
Selected packages passed checks and publication dry runs; nothing was uploaded.
EOF
if [[ "$run_tests" == false ]]; then
  echo "Test suites were not run. Verify CI results for the release commit before publishing."
fi
if [[ "$run_pana" == false ]]; then
  echo "Pana score gates were not run. Verify CI results for the release commit before publishing."
fi
