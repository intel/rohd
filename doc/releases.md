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
| [rohd_source_navigator](../packages/rohd_source_navigator) | Shared FLC data models and source-navigation utilities for debug viewers. | Independent pub.dev package; `dart pub publish` from its directory. | Its own `pubspec.yaml`. | Tag `rohd_source_navigator-v<version>`; release **rohd_source_navigator v<version>**. |
| [ROHD DevTools application](../rohd_devtools_extension) | Interactive hardware debug UI embedded in Dart DevTools. | Flutter web build produced by CI and bundled under `extension/devtools` in the ROHD pub.dev package; the application itself is not published to pub.dev. | Tracked by the containing ROHD release and the build's source/artifact commits, not an independent application release version. | Included in ROHD's tag and release notes; no separate release tag. The `artifacts` branch holds CI output, not an immutable release. |
| [ROHD VS Code extension](../rohd_extension) | Editor snippets, completions, and cross-probe source navigation. | GitHub Actions builds and attaches a VSIX when its GitHub release is published; a maintainer tests and publishes that VSIX to the VS Code Marketplace separately. | `rohd_extension/package.json`. | Tag `rohd-vscode-v<version>`; release `ROHD VS Code v<version>`, with `rohd-vscode-v<version>.vsix` attached automatically. |

The source-navigation library lives in `packages/rohd_source_navigator`, alongside
the other independently published libraries. Git dependencies following the move
must use the new package path; older pinned commits retain `rohd_extension/dart`.
The VS Code extension still compiles its separate TypeScript implementation.
Tutorial applications are not independently released packages.

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

1. Select only the packages that need releasing. Set each package's target stable
   `major.minor.patch` version in its own `pubspec.yaml` and prepare its changelog
   entries. The preparation script reads those independent versions, promotes
   each selected package's `## Next Release` heading (or accepts an existing
   version heading), and synchronizes `Config.version` when ROHD is selected.
   It never rewrites package manifests or assigns ROHD's version to sub-packages.
2. Ensure each package has a README, license, changelog, and package-specific
   repository URL. Publishable dependencies must use hosted version constraints,
   not local paths or Git checkouts. Keep minimum versions tied to APIs used.
3. For checkout development, waveform and widgets use checked-in
   `pubspec_overrides.yaml` files. These files are excluded from publication;
   overrides apply only to the root package being resolved, not its consumers.
   The non-published DevTools app therefore also declares its own local overrides.
4. Verify the PR's CI results cover the relevant tests for the release commit,
   including DevTools app tests when shared widgets change. The General workflow
   has separate `Check rohd_hierarchy`, `Check rohd_waveform`,
   `Check rohd_devtools_widgets`, and `Check rohd_source_navigator` jobs for
   dependency resolution, formatting, fatal-info analysis, package tests, and
   isolated hosted dependency checks and Pana reports.
   These run alongside the root checks and DevTools app job; documentation
   deployment waits for all of them.
   Preparation skips local test suites by default and does not query GitHub or
   verify CI status.
   Use `--run-tests` to repeat selected package suites locally. ROHD's local
   tests require Icarus Verilog; Verilator is required in CI and when
   `ROHD_REQUIRE_VERILATOR=1`.
5. Run `tool/prepare_release.sh [--run-tests] [package ...]` on the preparation
   branch from the repository root. No package names selects all five; explicit
   names select only those packages. Versions come from their manifests, not
   command-line arguments. It validates selected metadata before making changes,
   fetches `main` from `intel/rohd`, and requires that commit to be an ancestor
   of the release branch's `HEAD`. When ROHD is selected, it also fetches
   `artifacts` and requires the artifact's source commit to match that fetched
   `main` commit, not the release branch's tip. It smoke-tests and installs that
   web build before preparing metadata, then runs ROHD's checks. Sub-package-only
   preparation leaves ROHD metadata and DevTools untouched. Each selected
   sub-package gets dependency resolution, formatting checks, and analysis in its
   own directory, plus isolated hosted dependency checks and Pana reports even
   when tests are skipped.
   Tests run when `--run-tests` is supplied. Selecting ROHD also
   compiles and packages a temporary VSIX using the same helper as the VS Code
   release workflow, even when test suites are skipped. Only after all
   enabled checks for selected packages pass does it run
   publication dry runs. It does not merge, rebase, change manifest versions,
   commit, tag, push, or upload anything. If a guard fails, incorporate the latest
   `main` or wait for its artifact workflow as appropriate, then rerun preparation.
6. To inspect archives without preparing metadata, run
   `tool/check_release.sh [package ...]`. Like preparation, it defaults to all five
   packages and accepts explicit names: `rohd`, `rohd_hierarchy`, `rohd_waveform`,
   `rohd_devtools_widgets`, and `rohd_source_navigator`. Each uses its existing
   version. The helper runs
   `dart pub publish --dry-run` in each selected Dart package directory or
   `flutter pub publish --dry-run` for widgets. Review
   warnings, included files, and compressed archive sizes. For ROHD, first prepare
   the verified DevTools build as above, then verify that
   `extension/devtools/build` is included and passes
   `tool/gh_actions/devtool/test_devtools_install.sh extension/devtools`.

Preparation runs the following checks before invoking `tool/check_release.sh`:

| Selected Package | Default Checks | Added With `--run-tests` |
| --- | --- | --- |
| `rohd` | `tool/run_checks.sh --skip-tests`: dependencies, formatting, analysis, API docs, and temporary-file checks; then `tool/package_vscode.sh` compiles and packages a temporary VSIX. | Simulator prerequisites and ROHD tests via `tool/run_checks.sh`. |
| `rohd_hierarchy`, `rohd_waveform`, `rohd_source_navigator` | In each package directory: `dart pub get`, `dart format --output=none --set-exit-if-changed .`, then `dart analyze --fatal-infos`; also isolated hosted dependency checks and a Pana report. | `dart test` in each selected package. |
| `rohd_devtools_widgets` | In its package directory: `flutter pub get`, `dart format --output=none --set-exit-if-changed .`, then `flutter analyze --fatal-infos`; also isolated hosted dependency checks and a Pana report. | `flutter test` in the widgets package. |

Artifact provenance verification and the DevTools installation smoke test always
run when ROHD is selected, even when test suites are skipped. The VSIX packaging
check also always runs for that selection and discards its temporary archive on
exit. It checks the current preparation branch, not the DevTools artifact branch.
Packaging failure stops preparation before any pub.dev dry runs. This catches
TypeScript compilation and VSCE packaging errors; it is not an interactive
extension smoke test or a Marketplace publication. Running
`tool/run_checks.sh` directly still includes tests by default; its `--skip-tests`
option is what preparation uses unless `--run-tests` is supplied.

Formatting is checked without rewriting files. Analyzer info diagnostics are
fatal. The script prints each sub-package stage and stops on the first failed
prerequisite or enabled check; no publication dry runs start unless all enabled
checks pass. An early failure such as a nonempty `tmp_test` directory
means later stages have not run. Review leftover test files before retrying.
The ordinary package checks use the current checkout's dependency overrides.
Both CI and preparation reuse the existing Pana runner:
`bash tool/gh_actions/pana_source.sh packages/<package> <dart|flutter>`.
Its package mode uses a disposable copy without checkout overrides, lockfiles,
generated resolution/build state, or repository-relative analyzer configuration.
Inline overrides are rejected; keep local overrides in `pubspec_overrides.yaml`.
It runs `pub get` and `pub downgrade`, each followed by fatal-info analysis of
`lib/`, using the selected SDK. Flutter analysis uses `--no-pub` to preserve the
downgraded resolution. Required dependencies must already be available on pub.dev;
there is no fallback to local packages. Command failures stop CI and preparation.
Pana's report is printed for review, but package scoring findings such as missing
examples or newer dependency major versions are advisory. No custom report parser
is used. The root's existing no-argument Pana invocation and score gate are
unchanged. Temporary copies are cleaned up on success or failure, and developers'
overrides are never removed or rewritten.

Pana does not run consumer tests. Final override-free tests and archive checks
are still required as described below. Tests for the separate DevTools
application remain a separate step when its shared widgets change.

Preparation examples (choose one):

```sh
# All five packages, using each manifest's version; rely on CI for test suites:
tool/prepare_release.sh

# All five packages, also running their test suites locally:
tool/prepare_release.sh --run-tests

# ROHD only:
tool/prepare_release.sh rohd

# ROHD only, including its test suite:
tool/prepare_release.sh --run-tests rohd

# ROHD plus hierarchy and waveform:
tool/prepare_release.sh rohd rohd_hierarchy rohd_waveform

# Only hierarchy and waveform:
tool/prepare_release.sh rohd_hierarchy rohd_waveform

# Only source navigator:
tool/prepare_release.sh rohd_source_navigator

# Source navigator and widgets, including both package test suites:
tool/prepare_release.sh --run-tests rohd_source_navigator rohd_devtools_widgets
```

Preparation requires Dart for YAML metadata parsing using the root package's
dependencies. Selecting any sub-package also requires Pana, installed with
`bash tool/gh_actions/install_pana.sh`, and network access to hosted dependencies.
Selecting widgets also requires Flutter, including the default all-package
selection. The Pana runner discovers Flutter from its executable or uses
`FLUTTER_ROOT` when set. Selecting ROHD also requires Node.js and npm for the VSIX
check; the release workflow uses Node.js 24. Explicit sub-package-only preparation
does not build the VSIX or require Node.js/npm.

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
tool/check_release.sh --validate-only
tool/check_release.sh --validate-only rohd_hierarchy rohd_waveform rohd_devtools_widgets
tool/check_release.sh rohd_hierarchy rohd_waveform rohd_devtools_widgets
tool/check_release.sh rohd_source_navigator
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
Both stub publication commands on a restricted PATH. Preparation tests also
stub package-check commands to verify their order, SDK choice, and failure handling.
They cover both the default skipped suites and the `--run-tests` mode, including
Pana prerequisites and failure before publication checks, VSIX failure, and
temporary-archive cleanup. The existing Pana runner's root mode, package isolation,
and failure propagation are covered by `bash tool/test/pana_source_test.sh`,
using stub SDK/Pana executables without network access. The shared
VSIX helper has isolated command and failure checks in
`bash tool/test/package_vscode_test.sh`. The root
checker's default and `--skip-tests` paths are covered by
`bash tool/test/run_checks_test.sh`, which also uses isolated command stubs.
They allow real Dart execution only for the metadata helper, never for publication
commands.
Its focused metadata tests run with
`dart test test/prepare_release_metadata_test.dart`.

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

`rohd_source_navigator` has only hosted Dart dependencies and can be published
independently of ROHD and the Flutter packages. Once its version is available on
pub.dev, consumers such as the ROHD Schematic Viewer can replace their Git
dependency with `rohd_source_navigator: ^0.1.0` and remove any Git override for
that package. Existing Dart imports remain unchanged. See the
[package README](../packages/rohd_source_navigator/README.md) for installation
instructions and API examples.

For each package, wait until its required dependencies are available on pub.dev,
then complete final validation from a clean disposable checkout of the release commit without
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
Before merging the preparation PR, verify that the VSIX builds. The default
`tool/prepare_release.sh` command (or an explicit selection including `rohd`)
does this using `tool/package_vscode.sh`. For an extension-only check, or to keep
a local VSIX for inspection and manual testing, run from the repository root:

```sh
bash tool/package_vscode.sh /absolute/path/to/check.vsix
```

Choose a new output path; the helper refuses to overwrite an existing archive.
It runs `npm ci` with the checked-in lockfile and `npm run package -- --out ...`;
the prepublish script compiles TypeScript before VSCE validates and packages the
extension. It neither installs the extension nor uploads anything. Review the
reported archive contents and any warnings. Packaging alone does not verify
activation, completions, or cross-probe behavior; smoke-test those in VS Code.

Local VSIX files are for pre-release checks only. The distributable is the VSIX
built from the release tag and attached by the release workflow. Publish that
exact downloaded asset to the Marketplace; do not substitute or rebuild a local
VSIX for publication.

1. Tag the reviewed source commit as `rohd-vscode-v<version>`, where `<version>`
   exactly matches `rohd_extension/package.json`. The tagged commit must include
   the [VS Code release workflow](../.github/workflows/release_vscode.yml).
2. Publish a GitHub release for that tag, choosing the previous same-component
   tag for auto-generated notes. Do not mark it as GitHub's latest release.
3. Wait for **Release ROHD VS Code Extension** to succeed. It checks out the
   release tag, verifies the version, runs the same `tool/package_vscode.sh`
   helper with Node.js 24, and
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
