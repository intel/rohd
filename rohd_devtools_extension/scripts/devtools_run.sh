#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

mode="${1:-}"
run_mode="${2:-}"

# VS Code's dependency-mode picker includes a human-readable description.
mode="${mode%% *}"

usage() {
  cat <<'USAGE'
Usage: scripts/devtools_run.sh <dependency-mode> <run-mode>

Dependency modes are handled by scripts/devtools_dev_mode.sh:
  hr-he-hv, lr-he-hv, hr-le-hv, lr-le-hv,
  hr-he-lv, lr-he-lv, hr-le-lv, lr-le-lv

Run modes:
  web-debug
  web-release
  linux-debug
  linux-release
USAGE
}

if [[ -z "$mode" || -z "$run_mode" ]]; then
  usage >&2
  exit 2
fi

bash scripts/devtools_dev_mode.sh "$mode"
flutter pub get

case "$run_mode" in
  web-debug)
    make web-run
    ;;
  web-release)
    make web/pkg
    bash scripts/free_ports.sh
    flutter run --release -d web-server --web-port=9099 --web-hostname=127.0.0.1 lib/main_standalone.dart
    ;;
  linux-debug)
    make widget-prepare assets/.staged
    flutter run -d linux lib/main_standalone.dart
    ;;
  linux-release)
    make widget-prepare assets/.staged
    flutter run --release -d linux lib/main_standalone.dart
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac