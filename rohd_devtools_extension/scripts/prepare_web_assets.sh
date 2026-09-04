#!/bin/bash
# Prepare the standalone web asset fallback from the canonical staged assets.
# ELK is always copied with its notice and complete EPL-2.0 license text.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SOURCE_ASSETS="$PROJECT_ROOT/assets"
WEB_ASSETS="$PROJECT_ROOT/web/assets"

"$PROJECT_ROOT/scripts/stage_assets.sh"

# Remove obsolete locations that could contain a second ELK copy.
rm -rf "$WEB_ASSETS/js"
rm -f "$WEB_ASSETS/elk_layout_only.js"

mkdir -p "$WEB_ASSETS/third_party"

echo "Copying the ELK distribution with notice and EPL-2.0 text..."
rm -rf "$WEB_ASSETS/third_party/elkjs" "$WEB_ASSETS/layout_bridge"
cp -a "$SOURCE_ASSETS/third_party/elkjs" "$WEB_ASSETS/third_party/"
cp -a "$SOURCE_ASSETS/layout_bridge" "$WEB_ASSETS/"

echo "Web ELK assets prepared successfully"
