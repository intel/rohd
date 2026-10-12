# Build Scripts

This directory contains scripts to support building the ROHD DevTools Extension.

## Scripts

### stage_assets.sh

Stages widget-owned assets into the local asset root.

This script:

- Resolves widget locations from `.dart_tool/package_config.json`, so it uses
  the selected hosted, Git, or local dependency source
- Keeps legacy local asset staging available for widget assets outside Flutter
  package asset declarations

The web app loads the ELK bundle, license notice, and invocation adapter from
the `rohd_schematic_viewer` package asset namespace. Flutter publishes them
under `assets/packages/rohd_schematic_viewer/`, so hosted builds do not require
a sibling viewer checkout.

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

1. **Asset Staging**: Resolve selected widget packages and stage legacy
   widget assets when needed
2. **Flutter Build**: Bundle viewer-declared assets through Flutter's package
   asset namespace

### Important Notes

- Do not modify files in `rohd-schematic-viewer` or `rohd-wave-viewer` without testing those changes in their standalone apps first
- Assets are copied (not symlinked) because Flutter's asset system doesn't follow symlinks
- Run `make stage-js` before any build if legacy widget assets have changed
