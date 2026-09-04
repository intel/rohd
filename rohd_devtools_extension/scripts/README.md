# Build Scripts

This directory contains scripts to support building the ROHD DevTools Extension.

## Scripts

### stage_assets.sh

Stages the viewer-owned ELK distribution into the local asset root.

This script:

- Stages the pinned, unmodified ELK.js bundle at
`assets/third_party/elkjs/elk.bundled.js`
- Stages ELK's `NOTICE.md` and `LICENSES/EPL-2.0.txt` beside that bundle
- Stages locally owned invocation adapters at `assets/layout_bridge/`

**Usage:**

```bash
./scripts/stage_assets.sh
```

Or via Makefile:

```bash
make stage-js
```

## Build Process

The build process uses the Makefile at the project root. See `../Makefile` for all available targets.

### Key Steps

1. **Asset Staging**: Run `rohd-schematic-viewer`'s `elk-assets` target to prepare its ELK distribution
2. **Asset Copying**: Copy `third_party/elkjs/` and `layout_bridge/` together into the local assets
3. **Flutter Build**: Run `flutter build` with the staged assets

### Important Notes

- Do not modify files in `rohd-schematic-viewer` or `rohd-wave-viewer` without testing those changes in their standalone apps first
- Assets are copied (not symlinked) because Flutter's asset system doesn't follow symlinks
- Run `make stage-assets` before any build if assets have been updated in `rohd-schematic-viewer`
