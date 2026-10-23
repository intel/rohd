#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

run_mode="${1:-}"

usage() {
  cat <<'USAGE'
Usage: scripts/devtools_run.sh <run-mode>

Dependency sources are selected separately with scripts/devtools_dev_mode.sh.
This command runs using the currently generated dependency configuration.

Run modes:
  web-debug
  web-release
  linux-debug
  linux-release
USAGE
}

if [[ -z "$run_mode" ]]; then
  usage >&2
  exit 2
fi

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