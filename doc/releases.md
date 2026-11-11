# Releases

ROHD's packages and VS Code extension have independent versions and release
schedules. Release only the components that need an update.
The [release tools](../tool/release/README.md) prepare and check releases;
they do not publish packages, create tags, or push changes.

## Release Inventory

| Component | Publish from | Version source | Git tag |
| --- | --- | --- | --- |
| [rohd](../lib) | Repository root: `dart pub publish` | Root `pubspec.yaml`, synchronized with `Config.version` | `v<version>` |
| [rohd_hierarchy](../packages/rohd_hierarchy) | Its package directory: `dart pub publish` | Its `pubspec.yaml` | `rohd_hierarchy-v<version>` |
| [rohd_waveform](../packages/rohd_waveform) | Its package directory: `dart pub publish` | Its `pubspec.yaml` | `rohd_waveform-v<version>` |
| [rohd_devtools_widgets](../packages/rohd_devtools_widgets) | Its package directory: `flutter pub publish` | Its `pubspec.yaml` | `rohd_devtools_widgets-v<version>` |
| [rohd_source_navigator](../packages/rohd_source_navigator) | Its package directory: `dart pub publish` | Its `pubspec.yaml` | `rohd_source_navigator-v<version>` |
| [rohd_live_debugger](../packages/rohd_live_debugger) | Its package directory: `dart pub publish` | Its `pubspec.yaml`, synchronized with the DevTools config and app | `rohd_live_debugger-v<version>` |
| [ROHD VS Code extension](../rohd_extension) | VS Code Marketplace | `rohd_extension/pubspec.yaml` | `rohd-vscode-v<version>` |

The [DevTools application](../rohd_devtools_extension) is private; its web build
ships in `rohd_live_debugger`. It has no separate pub.dev release or tag.
Tutorial applications are not independently released.

## Publication Order

Publish a dependency before a consumer **when the consumer requires a version
that is not yet available on pub.dev**. One safe order when releasing all six
packages is:

1. `rohd_hierarchy`
2. `rohd_source_navigator` (independent)
3. `rohd` (depends on `rohd_hierarchy`)
4. `rohd_waveform` (depends on `rohd_hierarchy`)
5. `rohd_devtools_widgets` (depends on `rohd` and `rohd_hierarchy`)
6. `rohd_live_debugger`

`rohd` and `rohd_waveform` may swap places, and `rohd_source_navigator` may be
released at any time. The debugger package and ROHD do not depend on each other.
The private debugger application has build dependencies on ROHD and related
packages; ensure those dependencies and its verified build are ready. When
migrating from the embedded extension, release the ROHD version that removes
the old extension before the debugger to avoid duplicate tabs.

## Pub.dev Preparation

1. Use a preparation branch and PR containing the latest upstream `main`.
   Select the packages to release, set each target stable version in its own
   `pubspec.yaml`, and prepare its changelog. Ensure each package has a README,
   license, changelog, repository URL, and hosted dependency constraints.
2. Verify the relevant CI results for the release commit, including DevTools app
   tests when shared widgets change. Preparation does not verify CI status.
3. From the repository root, run the preparation helper for the selected
   packages. Omit package names to select all six:

   ```sh
   tool/release/prepare_release.sh rohd_hierarchy rohd_waveform
   tool/release/prepare_release.sh --run-tests --run-pana rohd_live_debugger
   ```

   The helper reads each manifest version, promotes a `## Next Release`
   changelog heading or accepts an existing version heading, and synchronizes
   `Config.version` when ROHD is selected. It checks dependencies, formatting
   and analysis; selecting ROHD also runs the root checks and builds a temporary
   VSIX. Tests and sub-package Pana checks are skipped by default: use
   `--run-tests` and `--run-pana` to run them locally, or verify those checks in
   CI. Dart is required; Flutter is required for widgets, including the default
   all-package selection. ROHD's VSIX check also requires Node.js and npm, and
   `--run-pana` requires Pana. Simulator tests have additional prerequisites.
   The helper stops on failure and runs publication dry runs only after the
   enabled checks pass. It never uploads, commits, tags, pushes, or merges.
4. When releasing `rohd_live_debugger`, ensure the debugger package version,
   `extension/devtools/config.yaml`, installer fallback config, and private
   Flutter app version match. The helper fetches the DevTools artifact built
   from upstream `main`, verifies its source commit and configuration,
   smoke-tests it, and installs it into the debugger package. The artifact must
   match the current upstream `main`; debugger implementation changes must land
   on `main` and its artifact workflow must complete first. ROHD-only
   preparation does not fetch this artifact.
5. Review the working tree and the archive dry runs. To check archives without
   preparing metadata:

   ```sh
   tool/release/check_release.sh --validate-only
   tool/release/check_release.sh rohd rohd_live_debugger
   ```

   This helper only runs `pub publish --dry-run`, reports failures and warnings,
   and can update dependency caches or lockfiles. It temporarily adjusts the
   root ignore rule for nested packages, as described below. Verify that:

   - ROHD includes its library and excludes `packages/`, the private app, the
     VS Code extension, root `extension/devtools/`, and `pubspec_overrides.yaml`.
   - `rohd_live_debugger` includes `extension/devtools/config.yaml` and the
     complete `extension/devtools/build/` payload. Check discovery with
     `tool/gh_actions/devtool/test_devtools_install.sh packages/rohd_live_debugger`.

   An old ignored root `extension/devtools/` directory can trigger a Pub
   DevTools warning even though it is excluded from the ROHD archive. Use a
   clean checkout for the final check; do not delete another developer's build.
6. Before publication, validate hosted dependency resolution, analysis, tests,
   and the archive without local dependency overrides or reused path-based
   lockfiles in a disposable checkout or isolated copy. Local workspace checks
   alone do not prove consumers can resolve hosted dependencies. Workspace
   members copied outside the workspace need `resolution: workspace` removed
   from the **copy**. Never remove another developer's overrides.
   `tool/release/run_pana.sh [package ...]` runs isolated compatibility and
   Pana checks; Pana does not replace consumer tests. For an optional local
   registry rehearsal, see [Hosted Package Testing With unpub](local_pub_testing.md).

The root `pubspec_overrides.yaml` contains checkout workspace membership and is
not published. Keep workspace paths and local overrides out of published
manifests. Pana score gates are defined in
[`pana_source.sh`](../tool/gh_actions/pana_source.sh).

## Manual Pub.dev Publication

Only a maintainer publishes, after reviewing the archive and confirming that
required dependency versions are available. Run `dart pub publish` from the
selected package directory, or `flutter pub publish` for widgets.

The root `.pubignore` excludes `/packages/` from the ROHD archive. Pub also
applies that rule when publishing a package within `packages/`, so temporarily
remove **only** the `/packages/` line before publishing a nested package.
Restore it immediately afterward, even on failure. Confirm it is restored
before a root ROHD dry run or publication. The temporary ignore edit does not
change the release source commit.

`check_release.sh` performs this toggle automatically for nested-package dry
runs and restores the original file. Do not edit `.pubignore` or run another
publication or release check concurrently. If the helper is forcibly stopped or
detects a concurrent edit, it retains `.pubignore-release.lock/original` for
recovery. Confirm the helper is no longer running, restore the `/packages/`
rule without discarding other edits, and remove the lock directory.

Confirm each version on pub.dev, then tag the reviewed preparation-branch commit
used for publication and create its GitHub release. Record that source commit;
for the debugger also record the DevTools `main` and artifact commits. Merge the
preparation PR after the selected packages are published; do not move release
tags to a later merge or squash commit. Start a new pending changelog section
for subsequent changes rather than rewriting published notes.

### Core API migration for 0.7.0

See the [ROHD 0.7.0 migration guide](rohd_0_7_migration.md) for removed APIs
and their replacements.

## GitHub Releases

Create an annotated tag and GitHub release for each component using the
inventory's tag convention. Bare `v<version>` tags are reserved for ROHD.
Point the tag at the exact reviewed source commit; multiple component tags may
use the same commit, but never move or reuse a published tag.

Use the component changelog for release notes and link to its pub.dev package or
Marketplace listing. For generated notes, select the previous tag for that
**same component**; omit it for a first release. Only ROHD framework releases
should be marked GitHub's latest release. Mark a release as a prerelease only
when its version is a prerelease.

Publish the GitHub release after the pub.dev version is available. GitHub source
archives contain the whole repository, not just the component. Tags and GitHub
releases do not themselves publish to pub.dev or the Marketplace.

## VS Code Publication

1. Set the version in `rohd_extension/pubspec.yaml`, run
   `make -C rohd_extension sync-version`, and prepare release notes. The pubspec
   is authoritative; do not edit the generated npm version metadata separately.
2. Check packaging before merging the preparation PR. ROHD preparation runs
   this check; for an extension-only check, use a new output path:

   ```sh
   bash tool/release/package_vscode.sh /absolute/path/to/check.vsix
   ```

   The helper compiles and verifies the VSIX but does not publish it. Packaging
   alone does not test activation, completions, or cross-probing.
3. Confirm the `intel-corporation` Marketplace publisher has an authorized
   maintainer and that both `intel-corporation.rohd-schematic-viewer` and
   `intel-corporation.rohd-wave-viewer` are public. The new
   `intel-corporation.rohd` listing does not update the older `rohd.rohd`
   listing; deprecate the old listing with a migration message after the new
   one is public, rather than deleting it.
4. Tag the reviewed commit `rohd-vscode-v<version>`. Wait for **Extension
   release artifact** to verify the listing prerequisites, build the VSIX, and
   upload the VSIX and checksum as a 90-day Actions artifact. Download that
   artifact, verify its checksum, and smoke-test the exact VSIX in VS Code.
   An authorized Marketplace administrator uploads that same VSIX, not the
   artifact ZIP or a rebuilt binary.
5. Publish the GitHub release for the tag, without marking it as latest. Wait
   for **Release ROHD VS Code Extension** to attach the VSIX and checksum.
   Workflows do not publish to the Marketplace or create tags or releases.
   Rerun a failed workflow after fixing its cause; do not overwrite a published
   asset with a different build.
