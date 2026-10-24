#!/usr/bin/env bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause

set -euo pipefail

usage() {
  echo "Usage: bash tool/local_pub.sh <experiment-directory> <command> [arguments ...]"
  echo "Run a command with an isolated Pub cache and a loopback hosted registry."
  echo "LOCAL_PUB_URL defaults to http://localhost:8081."
  echo "The server must already be running; this helper never publishes on its own."
}

if [[ $# -eq 1 && "$1" == --help ]]; then
  usage
  exit 0
fi
if [[ $# -lt 2 ]]; then
  usage >&2
  exit 2
fi

url="${LOCAL_PUB_URL:-http://localhost:8081}"
if [[ ! "$url" =~ ^http://(localhost|127\.0\.0\.1|\[::1\]):([0-9]{1,5})/?$ ]]; then
  echo "error: LOCAL_PUB_URL must be an HTTP loopback URL with an explicit port." >&2
  exit 2
fi
port="${BASH_REMATCH[2]}"
if (( 10#$port < 1 || 10#$port > 65535 )); then
  echo "error: LOCAL_PUB_URL port must be between 1 and 65535." >&2
  exit 2
fi

experiment="$1"
shift
mkdir -p "$experiment"
experiment="$(cd "$experiment" && pwd)"
export PUB_CACHE="$experiment/pub-cache"
export PUB_HOSTED_URL="${url%/}"
mkdir -p "$PUB_CACHE"
printf 'Local Pub registry: %s\nIsolated Pub cache: %s\n' "$PUB_HOSTED_URL" "$PUB_CACHE" >&2
exec "$@"
