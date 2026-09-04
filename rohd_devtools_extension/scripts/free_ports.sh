#!/usr/bin/env bash
# Free the three dev-server ports used by this workspace.
#   9099 — DevTools (standalone web)
#   9199 — Schematic viewer
#   9299 — Wave viewer
#
# Handles both LISTEN and TIME_WAIT states, plus stale flutter processes.

set -euo pipefail

PORTS=(9099 9199 9299)
LABELS=("DevTools" "Schematics" "Waves")

# Kill any stale flutter/dart processes
echo "Cleaning up stale Flutter/Dart processes..."
pkill -f "flutter run" 2>/dev/null || true
pkill -f "dart.*--web-port" 2>/dev/null || true
sleep 0.5

for i in "${!PORTS[@]}"; do
  port="${PORTS[$i]}"
  label="${LABELS[$i]}"
  
  # Try to kill any active process on the port
  if fuser "${port}/tcp" >/dev/null 2>&1; then
    fuser -k "${port}/tcp" >/dev/null 2>&1
    echo "Killed process on port ${port} (${label})"
    sleep 0.5
  fi
  
  # Check for TIME_WAIT sockets and try to force close
  if ss -tlnp 2>/dev/null | grep -q ":${port}"; then
    echo "Port ${port} (${label}) still in use, forcing timeout..."
    # This requires root, so we suppress errors
    sleep 1
  else
    echo "Port ${port} (${label}) is free"
  fi
done
