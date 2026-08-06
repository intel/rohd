#!/bin/bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# prepare_release.sh
# Prepare ROHD for a release without publishing it.
#
# Usage (from repo root):
#   tool/prepare_release.sh <version>
#
# 2026 July 30
# Author: Max Korbel <max.korbel@intel.com>

set -euo pipefail

# Require an explicit stable semantic version so an accidental invocation cannot
# mutate release metadata with an incomplete or pre-release version.
if [[ $# -ne 1 || ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 <major.minor.patch>" >&2
  exit 2
fi

# Resolve all paths and source provenance before changing the working tree.
readonly VERSION="$1"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
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
tool/gh_actions/check_tmp_test.sh

# Fetch the official artifact build without depending on a locally named remote.
echo "Fetching the ROHD DevTools build from $ARTIFACT_REPOSITORY ($ARTIFACT_BRANCH)..."
git fetch --quiet --no-tags "$ARTIFACT_REPOSITORY" "refs/heads/$ARTIFACT_BRANCH"
readonly ARTIFACT_COMMIT="$(git rev-parse FETCH_HEAD)"
readonly ARTIFACT_SOURCE_COMMIT="$(git rev-parse "$ARTIFACT_COMMIT^")"

# The artifact workflow creates its commit directly on top of the source commit.
# Refuse a stale build rather than packaging DevTools from a different revision.
if [[ "$ARTIFACT_SOURCE_COMMIT" != "$SOURCE_COMMIT" ]]; then
  echo "The DevTools artifact is stale." >&2
  echo "  Current source:  $SOURCE_COMMIT" >&2
  echo "  Artifact source: $ARTIFACT_SOURCE_COMMIT" >&2
  echo "Wait for the artifact workflow for the current source commit to finish." >&2
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

# Synchronize every framework version declaration and promote the pending
# changelog section to the requested release number.
sed -i "0,/^version: .*/s//version: $VERSION/" pubspec.yaml
sed -i \
  "0,/static const String version = '.*';/s//static const String version = '$VERSION';/" \
  lib/src/utilities/config.dart

if grep -q "^## $VERSION$" CHANGELOG.md; then
  :
elif grep -q '^## Next release$' CHANGELOG.md; then
  sed -i "0,/^## Next release$/s//## $VERSION/" CHANGELOG.md
else
  echo "CHANGELOG.md needs a '## Next release' or '## $VERSION' heading." >&2
  exit 1
fi

if ! grep -q "^version: $VERSION$" pubspec.yaml ||
    ! grep -q "static const String version = '$VERSION';" \
      lib/src/utilities/config.dart; then
  echo "Failed to synchronize release version $VERSION." >&2
  exit 1
fi

# Build the VS Code extension and leave its VSIX ready for manual publishing.
echo "Building the ROHD VS Code extension..."
npm --prefix rohd_extension ci
npm --prefix rohd_extension run package

# Run the same checks used for normal development and reject malformed diffs.
# Publishing remains a separate, intentionally manual operation.
tool/run_checks.sh
git diff --check

cat <<EOF

ROHD $VERSION is prepared from source commit $SOURCE_COMMIT.
DevTools artifact commit: $ARTIFACT_COMMIT

Review the changelog and working tree before performing the manual publish step.
EOF