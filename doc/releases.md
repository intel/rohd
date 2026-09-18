# Releases

## Release Inventory

The libraries and VS Code extension in this repository have independent versions
and release schedules. Releasing ROHD does not require releasing every component,
and a sub-package or VS Code extension release does not require a new ROHD
version. The DevTools application is the exception: its web build ships with
ROHD. Bump dependency constraints only when a consumer needs a newer version;
versions do not need to match across components.

In the table below, `<version>` means the version of the component being
released, not a repository-wide version.

| Component and Source | Purpose | Distribution and Release | Version Source | GitHub Tracking |
| --- | --- | --- | --- | --- |
| [rohd](../lib) | main framework | Independent pub.dev package, published with `dart pub publish` from the repository root; includes the DevTools web build. | Root `pubspec.yaml`, synchronized with `Config.version`. | Tag `v<version>`; release **ROHD v<version>**. |
| [rohd_hierarchy](../packages/rohd_hierarchy) | Shared hierarchy models, addressing, adapters, and search. | Independent pub.dev package; `dart pub publish` from its directory. | Its own `pubspec.yaml`. | Tag `rohd_hierarchy-v<version>`; release **rohd_hierarchy v<version>**. |
| [rohd_waveform](../packages/rohd_waveform) | Shared waveform models and data services. | Independent pub.dev package; `dart pub publish` from its directory. | Its own `pubspec.yaml`. | Tag `rohd_waveform-v<version>`; release **rohd_waveform v<version>**. |
| [rohd_devtools_widgets](../packages/rohd_devtools_widgets) | Reusable Flutter controls and utilities for debug viewers. | Independent pub.dev package; `flutter pub publish` from its directory. | Its own `pubspec.yaml`. | Tag `rohd_devtools_widgets-v<version>`; release **rohd_devtools_widgets v<version>**. |
| [ROHD DevTools application](../rohd_devtools_extension) | Interactive hardware debug UI embedded in Dart DevTools. | Flutter web build produced by CI and bundled under `extension/devtools` in the ROHD pub.dev package; the application itself is not published to pub.dev. | Tracked by the containing ROHD release and the build's source/artifact commits, not an independent application release version. | Included in ROHD's tag and release notes; no separate release tag. The `artifacts` branch holds CI output, not an immutable release. |
| [ROHD VS Code extension](../rohd_extension) | Editor snippets, completions, and cross-probe source navigation. | GitHub Actions builds and attaches a VSIX when its GitHub release is published; a maintainer tests and publishes that VSIX to the VS Code Marketplace separately. | `rohd_extension/package.json`. | Tag `rohd-vscode-v<version>`; release `ROHD VS Code v<version>`, with `rohd-vscode-v<version>.vsix` attached automatically. |

The internal Dart source-navigation port in `rohd_extension/dart` uses
`publish_to: none` and has no independent release or tag. The VS Code extension
compiles its TypeScript implementation, not the Dart port. Tutorial applications
are also not independently released packages.

## GitHub Strategy

Create an annotated tag and a GitHub release for each independently published
component version. Tags identify immutable source; GitHub releases make the
component's notes and distribution links discoverable. Use the naming conventions
in the inventory, preserving ROHD's existing `v<version>` tag history. Bare
`v<version>` tags are reserved for ROHD, not sub-packages or the VS Code extension.

- Point each tag at the exact reviewed commit used to publish that component.
   Multiple component tags may point at the same commit.
- Title each release with the component name and version, as in the table above.
- Use the component's changelog as the curated, readable summary of its changes.
   Link to its pub.dev version or Marketplace listing, identify its source
   directory, and describe compatibility changes.
- When using **Generate release notes**, explicitly set **Previous tag** to the
   previous release tag for the same component: `v<version>` for ROHD,
   `rohd-vscode-v<version>` for the VS Code extension, or the matching package
   prefix for a sub-package. Do not assume the automatically selected tag is
   correct when releases of other components occur in between. For a component's
   first release, there is no previous same-component tag; do not substitute
   another component's release. Auto-generated notes may include unrelated PRs
   in the comparison range; that is fine and does not require manual filtering.
- Reserve GitHub's **Latest** designation for ROHD framework releases. Disable
   **Set as the latest release** for sub-packages and the VS Code extension (or
   use `--latest=false` with `gh release create`). A pre-1.0 version is not
   automatically a prerelease;
  mark prereleases only when publishing a prerelease version.
- Do not move or reuse published tags. Publish fixes under a new version.
- GitHub source archives contain the whole repository, not just the named
   component. Direct library consumers to pub.dev and extension users to the
   Marketplace or the matching VSIX release asset.

Draft release notes during preparation. For pub.dev packages, publish the GitHub
release after the matching version is available on pub.dev. For the VS Code
extension, publishing the GitHub release triggers VSIX attachment; Marketplace
publication follows testing of that asset. Tags and GitHub releases do not
automatically publish to pub.dev or the Marketplace. Commits, tag creation,
pushes, and publication are separate maintainer actions.

## Pub.dev Preparation

Use a dedicated preparation branch and PR. Publish the selected packages from
that branch, then merge the PR after their releases have succeeded on pub.dev.
Before preparing, incorporate the latest upstream `main` into the release branch
with a merge or rebase; the preparation PR itself does not need to be merged yet.

1. Select only the packages that need releasing. Update each package's
   `pubspec.yaml` version and promote its pending changelog section to that
   version. For ROHD, also update `Config.version` in
   `lib/src/utilities/config.dart`.
2. Ensure each package has a README, license, changelog, and package-specific
   repository URL. Publishable dependencies must use hosted version constraints,
   not local paths or Git checkouts. Keep minimum versions tied to APIs used.
3. For checkout development, waveform and widgets use checked-in
   `pubspec_overrides.yaml` files. These files are excluded from publication;
   overrides apply only to the root package being resolved, not its consumers.
   The non-published DevTools app therefore also declares its own local overrides.
4. Run analysis, formatting checks, tests, and API documentation generation for
   each changed package. Use `dart` for Dart packages and `flutter` for Flutter
   packages. For ROHD, run `tool/run_checks.sh`; Icarus Verilog is required and
   Verilator is required in CI. Test the DevTools app when shared widgets change.
5. On the preparation branch, wait for the DevTools artifact workflow for the
   latest upstream `main`, then run
   `tool/prepare_release.sh <version> [sub-package ...]` from the repository root,
   replacing `<version>` with the target ROHD version and optionally appending
   selected package names. It fetches `main` from `intel/rohd` and requires that
   commit to be an ancestor of the release branch's `HEAD`. It then fetches
   `artifacts` and requires the artifact's source commit to match that fetched
   `main` commit, not the release branch's tip. It smoke-tests and installs the
   web build, synchronizes ROHD versions, and runs checks. After those checks,
   it runs publication dry runs for ROHD and any selected sub-packages. It does
   not merge, rebase, change sub-package versions, commit, tag, push, or upload
   anything. If either guard fails, incorporate the latest `main` or wait for its
   artifact workflow as appropriate, then rerun preparation.
6. For independent package releases or to repeat archive checks, run
   `tool/check_release.sh <package> [package ...]`. Select from `rohd`,
   `rohd_hierarchy`, `rohd_waveform`, and `rohd_devtools_widgets`; each uses its
   existing version. The helper runs `dart pub publish --dry-run` in each selected
   Dart package directory or `flutter pub publish --dry-run` for widgets. Review
   warnings, included files, and compressed archive sizes. For ROHD, first prepare
   the verified DevTools build as above, then verify that
   `extension/devtools/build` is included and passes
   `tool/gh_actions/devtool/test_devtools_install.sh extension/devtools`.

The bundled DevTools is built from upstream `main`, not from preparation-branch
changes. Release metadata can differ on the preparation branch, but any DevTools
implementation changes, including changes to shared code it uses, must already
be in `main` and its artifact build to be included. Do not bypass the artifact
guard to package an older build. The source repository defaults to `intel/rohd`;
`ROHD_ARTIFACT_REPOSITORY` overrides the repository used for both fetches, and
`ROHD_ARTIFACT_BRANCH` overrides only the artifact branch name.

For example, validate a selection without invoking any SDK commands, then run
the selected dry runs:

```sh
tool/check_release.sh --validate-only rohd_hierarchy rohd_waveform rohd_devtools_widgets
tool/check_release.sh rohd_hierarchy rohd_waveform rohd_devtools_widgets
```

`--validate-only` checks package names, manifest presence, and SDK availability.
Unknown names and options are rejected before any SDK command runs; preparation
also validates its selection before fetching artifacts or changing files. The
helper has no upload mode, hard-codes `--dry-run`, and does not forward pub flags.
It reports each result and continues after a failed dry run, returning nonzero
if any package fails, including when pub treats warnings as a nonzero result.
Dry runs can resolve dependencies and update local caches or lockfiles; they
leave package versions and local override files unchanged. They do not prove
hosted dependency readiness when local overrides are present.

The helper's isolated regression checks run with
`bash tool/test/check_release_test.sh`. Preparation guard checks run with
`bash tool/test/prepare_release_test.sh` using temporary local Git repositories.
Both use fake SDK executables on a restricted PATH and cannot reach real Dart
or Flutter publication commands.

## Publication Order

Determine pub.dev publication order from the selected packages' dependency
constraints. When a consumer requires an unpublished dependency version, publish
that dependency first. If compatible dependency versions are already available
on pub.dev, the consumer can be released independently without a new dependency
release.

For example, `rohd_waveform` depends on `rohd_hierarchy`, and
`rohd_devtools_widgets` depends on both `rohd_hierarchy` and ROHD. These
dependencies determine ordering only when the required versions have not yet
been published. Sharing a repository or source commit does not require a
coordinated release.

For each package, wait until its required dependencies are available on pub.dev,
then validate from a clean disposable checkout of the release commit without
local dependency overrides or reused path-based lockfiles. Remove that checkout's
`pubspec_overrides.yaml`, run dependency resolution, analysis and tests again, and
repeat the publish dry run. A dry run using local overrides does not prove that
pub.dev consumers can resolve or use the package. Never remove a developer's
overrides from their working checkout just to perform this check.

After reviewing the final archive, publish from a reviewed, clean commit on the
preparation branch. A maintainer runs `dart pub publish` or `flutter pub publish`
from the selected package directory. Confirm each version on pub.dev, then create
its tag at the preparation-branch commit used for publication and publish its
GitHub release using the strategy above. Record the release source commit and,
for ROHD, both the DevTools source (`main`) and artifact commits in the release
notes. Once all selected packages have been published successfully, merge the
preparation PR; do not move release tags to a later merge or squash commit.
Start a new pending changelog section when subsequent changes are made; do not
rewrite notes for already published versions.

## VS Code Publication

Prepare the extension separately from pub.dev packages. Update its version in
`rohd_extension/package.json` and prepare extension-specific release notes.
From `rohd_extension`, run `npm ci` and `npm run package`; the prepublish script
compiles TypeScript before VSIX packaging. Use that local build for pre-release
checks.

1. Tag the reviewed source commit as `rohd-vscode-v<version>`, where `<version>`
   exactly matches `rohd_extension/package.json`. The tagged commit must include
   the [VS Code release workflow](../.github/workflows/release_vscode.yml).
2. Publish a GitHub release for that tag, choosing the previous same-component
   tag for auto-generated notes. Do not mark it as GitHub's latest release.
3. Wait for **Release ROHD VS Code Extension** to succeed. It checks out the
   release tag, verifies the version, runs `npm ci` and `npm run package`, and
   attaches `rohd-vscode-v<version>.vsix` to that release using `GITHUB_TOKEN`.
   Other component releases are skipped. Saving a draft or pushing a tag alone
   does not trigger the workflow.
4. Download and smoke-test the attached VSIX in VS Code, then have a maintainer
   publish that same file through Marketplace tooling. Confirm the Marketplace
   version and link it from the GitHub release notes.

If the build or upload fails, resolve the cause and rerun the failed workflow
job. An existing same-named asset is not overwritten; do not replace an already
published binary with a different build. The workflow only attaches the VSIX:
it does not publish to the Marketplace, create tags or releases, or change
release notes or the latest-release designation. Local Makefile install targets
update a developer's installation; they do not publish a release.

## Local Review Notes

`reviews/` is optional local working material, not a source or release artifact.
It is explicitly excluded at the repository root in both `.gitignore` and
`.pubignore`, so notes remain on disk without being committed or published.
The pub exclusion is intentional: `.pubignore` replaces `.gitignore` for package
publication. These rules do not remove already tracked files; check the archive
preview before publishing. Generated coverage and local dependency override
files are also excluded from publication.
