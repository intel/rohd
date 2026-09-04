#!/usr/bin/env bash
# Generic widget asset aggregator for ROHD Debugger
# Each widget can stage its own assets to build/assets/, this script aggregates them.
# This keeps the top-level Makefile completely generic and widget-agnostic.
#
# Backward compatibility: also checks widget source directories if build/assets/ not found.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="${RELEASE_DIR:-$HOME/release}"
SCHEMATIC_VIEWER="$RELEASE_DIR/rohd-schematic-viewer"
WAVE_VIEWER="$RELEASE_DIR/rohd-wave-viewer"
ASSETS_DEST="${ROOT}/assets"

echo "Aggregating staged assets from all widgets..."
mkdir -p "$ASSETS_DEST"

# The schematic viewer owns the ELK distribution. Stage its bundle, license
# notice, and browser invocation adapter together for embedded DevTools builds.
if [ -f "$SCHEMATIC_VIEWER/assets/js/elk.bundled.js" ] && \
    [ -f "$SCHEMATIC_VIEWER/assets/licenses/elkjs_LICENSES.txt" ] && \
    [ -f "$SCHEMATIC_VIEWER/js_bridge/elk_layout_only.js" ]; then
    echo "  Staging self-contained ELK distribution from rohd-schematic-viewer..."
    rm -rf "$ASSETS_DEST/third_party/elkjs" "$ASSETS_DEST/layout_bridge"
    mkdir -p "$ASSETS_DEST/third_party/elkjs/LICENSES" "$ASSETS_DEST/layout_bridge"
    cp "$SCHEMATIC_VIEWER/assets/js/elk.bundled.js" \
        "$ASSETS_DEST/third_party/elkjs/"
    cp "$SCHEMATIC_VIEWER/assets/licenses/elkjs_LICENSES.txt" \
        "$ASSETS_DEST/third_party/elkjs/LICENSES/"
    cp "$SCHEMATIC_VIEWER/js_bridge/elk_layout_only.js" \
        "$ASSETS_DEST/layout_bridge/"
    rm -rf "$ASSETS_DEST/js"
    rm -f "$ASSETS_DEST/elk_layout_only.js"
elif [ -d "$SCHEMATIC_VIEWER" ]; then
    echo "  Warning: rohd-schematic-viewer ELK distribution is incomplete; skipping ELK staging."
fi

# Iterate through all known widget directories and collect their staged assets
for widget_dir in "$SCHEMATIC_VIEWER" "$WAVE_VIEWER"; do
    if [ ! -d "$widget_dir" ]; then
        continue
    fi
    
    widget=$(basename "$widget_dir")
    
    # Skip non-widget directories
    case "$widget" in
        lib|test|assets|build|web|scripts|packages|linux|shared|.*) continue ;;
    esac
    
    widget_built_assets="$widget_dir/build/assets"
    
    # Check for properly-staged widget assets first
    if [ -d "$widget_built_assets" ]; then
        echo "  Collecting assets from $widget/build/assets/..."
        cp -r "$widget_built_assets"/* "$ASSETS_DEST/" 2>/dev/null || true
    else
        # Backward compatibility: check for common widget asset source locations
        echo "  Checking $widget for source assets..."
        
        # Check for js_bridge directory (e.g., rohd-schematic-viewer/js_bridge/)
        if [ "$widget" != "rohd-schematic-viewer" ] && [ -d "$widget_dir/js_bridge" ]; then
            echo "    Found js_bridge, copying..."
            mkdir -p "$ASSETS_DEST/js"
            cp -r "$widget_dir/js_bridge/"* "$ASSETS_DEST/js/" 2>/dev/null || true
            # Also copy root-level js bridge files
            cp -r "$widget_dir/js_bridge/"*.js "$ASSETS_DEST/" 2>/dev/null || true
        fi
        
        # Check for assets directory
        if [ -d "$widget_dir/assets" ]; then
            echo "    Found assets, copying..."
            if [ "$widget" != "rohd-schematic-viewer" ]; then
                mkdir -p "$ASSETS_DEST/js"
                [ -d "$widget_dir/assets/js" ] && cp -r "$widget_dir/assets/js/"* "$ASSETS_DEST/js/" 2>/dev/null || true
            fi
            # Copy root-level asset files
            find "$widget_dir/assets" -maxdepth 1 -type f -exec cp {} "$ASSETS_DEST/" \; 2>/dev/null || true
        fi
    fi
done

echo "Assets aggregated to: $ASSETS_DEST/"
echo "Flutter will bundle from assets/ into:"
echo "  - build/web/assets/ (for web builds)"
echo "  - build/linux/assets/ (for Linux native builds)"

# Ensure WASM pkg files exist in web/ for dev server (flutter run -d web-server).
# The wellen_bridge WASM is built in rohd-wave-viewer/web/pkg/ and needs to be
# copied into the host app's web/ directory for the <script> tag in index.html.
WASM_PKG="${WAVE_VIEWER}/web/pkg"
WEB_PKG="${ROOT}/web/pkg"
if [ -d "$WASM_PKG" ]; then
    echo "Copying WASM pkg for web dev server..."
    rm -rf "$WEB_PKG"
    mkdir -p "$(dirname "$WEB_PKG")"
    cp -R "$WASM_PKG" "$WEB_PKG"
else
    if [ -L "$WEB_PKG" ]; then
        echo "Removing stale WASM pkg symlink..."
        rm -f "$WEB_PKG"
    fi
    echo "Warning: WASM pkg not found at $WASM_PKG. Run 'make wasm' first for web builds."
fi
