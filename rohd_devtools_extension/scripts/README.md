# Build Scripts

This directory contains scripts to support building the ROHD DevTools Extension.

## Scripts

### devtools_run.sh

Runs `flutter pub get` from the repository's Pub workspace root, then prepares
and launches the selected web or Linux mode from the extension directory.
Use `bash scripts/devtools_run.sh --help` to list the supported modes.

From the repository root, run `bash tool/test/devtools_workspace_test.sh` to
check command routing and Makefile Pub invocations without building an app.

### install_viewer_artifacts.sh

Runs the selected `dart_wellen` package's artifact installer. Local and hosted
files are verified against that package's manifest; Git consumers can download
the pinned, checksummed bundle. This script only installs/verifies prebuilt
artifacts. The selected viewer determines the bridge version.
Missing manifests, unavailable bundles, and checksum mismatches
fail explicitly.

Use `make viewer-artifacts` to install or verify the selected dependency's
artifacts without building the debugger.

### stage_assets.sh

Stages widget-owned assets into the local asset root.

This script:

- Resolves widget locations from the Pub workspace root's
  `.dart_tool/package_config.json`, so it uses the selected hosted, Git, or
  local dependency source
- Keeps legacy local asset staging available for widget assets outside Flutter
  package asset declarations
- Refreshes ignored `web/dart_wellen` from the selected `dart_wellen` package, including
  its license notices; it never falls back to a debugger-vendored runtime

Run `flutter pub get` from the repository root before staging assets. Pub
workspaces have one package configuration at the workspace root, not one per
member package.

The web app loads the ELK bundle, license notice, and invocation adapter from
the `rohd_schematic_viewer` package asset namespace. Flutter publishes them
under `assets/packages/rohd_schematic_viewer/`, so hosted dependencies do not require
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

These steps consume existing viewer artifacts. Missing Dart bindings or web
runtime files are errors, not a request to build dependencies from source.

### Important Notes

- Assets are copied (not symlinked) because Flutter's asset system doesn't follow symlinks
- Run `make stage-js` before any build if legacy widget assets have changed
