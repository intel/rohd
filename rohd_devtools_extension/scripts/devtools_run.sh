#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
workspace_root="$(cd -- "$script_dir/../.." && pwd)"
cd "$script_dir/.."

run_mode="${1:-}"

usage() {
  cat <<'USAGE'
Usage: scripts/devtools_run.sh <run-mode>

Dependency sources are selected separately with
tool/devtools/devtools_dev_mode.sh.
This command runs using the currently generated dependency configuration.

Run modes:
  web-debug
  web-release
  linux-debug
  linux-release
USAGE
}

case "$run_mode" in
  web-debug|web-release|linux-debug|linux-release) ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

(cd "$workspace_root" && flutter pub get)

case "$run_mode" in
  web-debug)
    make web-run
    ;;
  web-release)
    make web/dart_wellen
    bash scripts/free_ports.sh
    flutter run --release -d web-server --web-port=9099 --web-hostname=127.0.0.1 lib/main_standalone.dart
    ;;
  linux-debug)
    make assets/.staged
    flutter run -d linux lib/main_standalone.dart
    ;;
  linux-release)
    make assets/.staged
    flutter run --release -d linux lib/main_standalone.dart
    ;;
esac