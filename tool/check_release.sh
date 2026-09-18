#!/bin/bash

set -euo pipefail

usage() {
  echo "Usage: $0 [--validate-only] <package> [package ...]"
  echo "Packages: rohd rohd_hierarchy rohd_waveform rohd_devtools_widgets"
  echo "Runs publication dry runs only; never uploads packages."
}

if [[ $# -eq 1 && "$1" == '--help' ]]; then
  usage
  exit 0
fi

validate_only=false
if [[ "${1:-}" == '--validate-only' ]]; then
  validate_only=true
  shift
fi
if [[ $# -eq 0 ]]; then
  usage >&2
  exit 2
fi

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
packages=()
directories=()
sdks=()

for package in "$@"; do
  case "$package" in
    rohd)
      directory="$REPO_ROOT"
      sdk=dart
      ;;
    rohd_hierarchy|rohd_waveform)
      directory="$REPO_ROOT/packages/$package"
      sdk=dart
      ;;
    rohd_devtools_widgets)
      directory="$REPO_ROOT/packages/$package"
      sdk=flutter
      ;;
    *)
      echo "Unsupported package or option: $package" >&2
      usage >&2
      exit 2
      ;;
  esac
  if [[ ! -f "$directory/pubspec.yaml" ]]; then
    echo "Missing package manifest: $directory/pubspec.yaml" >&2
    exit 2
  fi
  if ! command -v "$sdk" >/dev/null; then
    echo "Required SDK command not found: $sdk" >&2
    exit 2
  fi
  packages+=("$package")
  directories+=("$directory")
  sdks+=("$sdk")
done

if [[ "$validate_only" == true ]]; then
  echo "Selection validated; no SDK commands were run: ${packages[*]}"
  exit 0
fi

echo "Dry runs only. Package versions and local overrides are left unchanged."
echo "Local overrides can hide hosted dependency problems; repeat without them in a disposable checkout before publishing."
results=()
failed=0
for index in "${!packages[@]}"; do
  package="${packages[$index]}"
  directory="${directories[$index]}"
  sdk="${sdks[$index]}"
  printf '\n=== %s ===\n' "$package"
  if [[ "$package" == rohd ]] &&
      [[ ! -f "$REPO_ROOT/extension/devtools/build/index.html" ||
         ! -f "$REPO_ROOT/extension/devtools/config.yaml" ]]; then
    echo "ROHD requires its prepared DevTools build. Run tool/prepare_release.sh <version> first." >&2
    results+=("$package: FAILED (missing DevTools payload)")
    failed=1
    continue
  fi
  echo "Directory: $directory"
  echo "Command: $sdk pub publish --dry-run"
  if (cd "$directory" && "$sdk" pub publish --dry-run </dev/null); then
    results+=("$package: PASSED")
  else
    status=$?
    results+=("$package: FAILED (exit $status; see output above)")
    failed=1
  fi
done

printf '\nPublication dry-run summary:\n'
printf '  %s\n' "${results[@]}"
echo "No packages were uploaded. Nonzero pub results, including warnings, require review."
exit "$failed"
