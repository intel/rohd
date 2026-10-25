# Hosted Package Testing With unpub

Use this optional gate before real publication to test a graph of unpublished
packages through the Pub hosted protocol. It complements local-path and Git
tests; a publication dry run alone does not prove that another application can
install and use the archive.

The experiment must not change release versions or add localhost URLs to release
source. Use disposable staging directories, a private registry data directory,
and a fresh consumer cache. Nothing in this procedure publishes to pub.dev,
creates commits, or publishes VS Code extensions.

## Server Prerequisite

The existing implementation at
`~/Cockpit/publishable/local_pub_server` wraps `unpub` with:

- JSON-file metadata and tarball storage, without MongoDB;
- upload authentication bypass for local development; and
- a pub.dev upstream for packages that are not present locally.

Its entry point is `bin/server.dart`, with `pubspec.yaml` declaring `unpub`.
Reuse that implementation or an equivalent local hosted registry. This repository
does not vendor the server or require its development dependencies in ROHD's
workspace. The helper below is independent of the server implementation.

**Bind to loopback only.** The example server's default is `0.0.0.0`, and its
authentication bypass makes it unsuitable for a public or shared network.
Do not expose it through a public port forward. Use a free port rather than
stopping another user's service.

## Create an Isolated Experiment

Run from the ROHD repository root:

```bash
rohd_repo="$PWD"
experiment="$(mktemp -d /tmp/rohd-hosted-test.XXXXXXXX)"
export LOCAL_PUB_URL=http://localhost:18081
mkdir -p "$experiment/stage" "$experiment/consumer"
printf 'Experiment directory: %s\n' "$experiment"
```

Keep this directory path and URL for the other terminals. Do not reuse an old
registry's storage or your normal Pub cache.

In a separate terminal, start the existing server with the same experiment path:

```bash
cd ~/Cockpit/publishable/local_pub_server
UNPUB_HOST=127.0.0.1 \
UNPUB_PORT=18081 \
UNPUB_DATA_DIR=/tmp/rohd-hosted-test.REPLACE_ME/server-data \
  bash start_unpub_server.sh
```

The startup script resolves its own dependencies if its package configuration is
missing. Keep it running in the foreground; stop your server with Ctrl+C when
finished. Verify readiness before publishing:

```bash
curl --fail --location --silent --show-error \
  "$LOCAL_PUB_URL/api/packages/collection" >/dev/null
```

The readiness check exercises upstream fallback as well as the listener; the
server still needs network access for packages not hosted locally.

## Run Commands Against the Registry

Use the repository helper for each publisher or consumer command:

```bash
bash "$rohd_repo/tool/release/local_pub.sh" "$experiment" dart pub get
```

It sets `PUB_HOSTED_URL` and puts `PUB_CACHE` under the experiment directory for
that command only. It preserves the current directory, arguments, and exit
status, and accepts only HTTP loopback registry URLs with explicit ports.
It does not start a server, stage source, publish packages, or remove files.

The default URL is `http://localhost:8081`; keep `LOCAL_PUB_URL` exported when
using a different port. Do not globally export `PUB_HOSTED_URL` or point unrelated
shells at the test registry.

An explicit `publish_to` in a package takes precedence over the environment.
Inspect each staged manifest: it should omit `publish_to`, or specify the local
registry for this disposable experiment only. Never leave `publish_to: none`
on a package being published, and never run an upload if Pub prints pub.dev as
its destination.

## Stage Real Publication Candidates

Select the packages under test and work from copies, not their live checkout
directories. A useful inventory records package name, version, source commit,
archive checksum, and its unpublished dependencies.

For an ordinary standalone package, a starting copy is:

```bash
source_package="$rohd_repo/packages/rohd_hierarchy"
staged_package="$experiment/stage/rohd_hierarchy"
mkdir "$staged_package"
tar -C "$source_package" \
  --exclude=.git --exclude=.dart_tool \
  --exclude=pubspec.lock --exclude=pubspec_overrides.yaml \
  -cf - . | tar -C "$staged_package" -xf -
```

Use the package's producer-owned publication staging helper when one exists.
The example is not a universal archive filter: preserve the package's
`.pubignore`, licenses, generated API, declared assets, and required prebuilt
runtime. ROHD publication also requires its verified DevTools distribution.
Do not strip required build outputs merely because they were generated.

For workspace members, remove `resolution: workspace` in the disposable
manifest. For a workspace root staged without its members, remove `workspace:`
and its member list. Remove any inline `dependency_overrides`; actual
dependencies must be normal hosted version constraints. Checkout-only override
files, lockfiles, and package configurations must not mask missing publications.
Do not fix missing package APIs by adding path or Git overrides in the consumer.

These isolation adjustments belong only to the staging copy. Packaging changes
that are also needed on pub.dev belong in the producer repository and its
publication helper; registry URLs, authentication, and server storage do not.

### Wave Viewer Packages

The Wave Viewer publishes two independent packages:

1. `dart_wellen` owns generated Dart bindings, the matching JS/WASM pair,
   licenses, and artifact manifest/installer.
2. `rohd_wave_viewer` embeds it and declares a hosted `dart_wellen` constraint.

Use prepared outputs from the selected Wave Viewer worktree; never build the
viewer or Rust bridge from ROHD to satisfy a consumer dependency. Copy the
prepared `packages/dart_wellen` package, including its `.pubignore`, into the
staging area and remove `resolution: workspace` there.

Stage the embedding package with the producer helper:

```bash
wave_repo="$HOME/rohd-wave-viewer.worktrees/shared-packages-020"
bash "$wave_repo/tool/stage_hosted_viewer.sh" \
  "$experiment/stage/rohd_wave_viewer"
```

Before publishing, verify `dart_wellen` includes all four generated Dart files,
`tool/bridge_artifacts.json`, `tool/bridge_artifacts.build.json`,
`tool/bridge_artifacts.py`, and the JS/WASM and
license files under `web/pkg`. The embedding package must not duplicate that
payload. Both Flutter debug and release consume the manifest's declared release
WASM profile; Flutter mode does not select a Cargo build.

## Publish in Dependency Order

Publish each unpublished dependency before its consumers. For the current
package graph, inspect the selected manifests rather than assuming all versions
must change together. A typical partial order is:

1. `rohd_hierarchy`;
2. `rohd_waveform`, `rohd_source_navigator`, and other packages requiring it;
3. `rohd`, before widgets that depend on it;
4. `rohd_devtools_widgets` and `dart_wellen`, after their own dependencies;
5. `rohd_wave_viewer` and `rohd_schematic_viewer`, after their dependencies.

Packages already satisfied by pub.dev can use the server's upstream fallback.
Once a package name exists locally, do not assume its version list is merged
with pub.dev's: publish every version of that package needed by the experiment.

In each staged package directory:

```bash
cd "$experiment/stage/dart_wellen"
bash "$rohd_repo/tool/release/local_pub.sh" "$experiment" dart pub publish --dry-run
# Review the destination, warnings, and archive inventory before upload.
bash "$rohd_repo/tool/release/local_pub.sh" "$experiment" dart pub publish
```

Use `flutter pub` for Flutter packages. The interactive upload is deliberate;
the helper never invokes `publish` by itself. The current Dart SDK does not
expose a `publish --server` option: use the command-scoped environment instead.
Do not use `--skip-validation` to conceal packaging or dependency errors.
Review any known exact bridge-version warning separately from new warnings.

Verify what was registered:

```bash
curl --fail --silent --show-error \
  "$LOCAL_PUB_URL/api/packages/dart_wellen"
```

Inspect the served archive as well as the dry-run listing. An upstream response
for a package that has not been published locally is not proof of a successful
local upload.

## Test a Fresh Hosted Consumer

Create a standalone application outside every source Pub workspace. Its
manifest should use normal version constraints for packages under test, with no
path or Git dependencies or overrides. Use the registry environment consistently
so transitive dependencies such as `dart_wellen` also resolve through the server;
redirecting only `rohd_wave_viewer` with an explicit hosted URL is insufficient.

```bash
cd "$experiment/consumer"
# Create the test application's pubspec.yaml and source here.
bash "$rohd_repo/tool/release/local_pub.sh" "$experiment" flutter pub get
bash "$rohd_repo/tool/release/local_pub.sh" "$experiment" flutter analyze
bash "$rohd_repo/tool/release/local_pub.sh" "$experiment" flutter test
```

Check the exact result, not just Pub success:

- `pubspec.lock` records hosted sources at the test registry and expected versions.
- `.dart_tool/package_config.json` points at this experiment's hosted cache,
  not a source checkout, Git cache, or workspace sibling.
- The cached packages contain the required API, Flutter assets, JS/WASM, and
  notices. No checkout-only overrides or old staged assets mask omissions.
- For Wave Viewer, resolve the installed `dart_wellen` root from that package
  configuration and run `python3 <root>/tool/bridge_artifacts.py verify`.
  Verification must succeed without downloading the GitHub bundle.
- Stage the cached package's runtime and exercise actual waveform loading in
  the embedding application. Check browser initialization and runtime errors,
  not only compilation. No Cargo, binding generation, or external viewer builds
  may run.

Use an isolated copy of the actual DevTools app for the final integration gate.
The minimal consumer catches packaging mistakes; it does not replace application
tests or justify changing the live checkout's working dependency selection.

## Repeat Without Bumping Versions

The existing `unpub` implementation rejects a second upload of the same package
version. For another candidate, stop the experiment's server and create a
**new experiment directory**, server data directory, staging area, and consumer.
Use a fresh cache and lockfile so an earlier archive cannot satisfy the test.
This permits reusing the same intended release versions without overwriting
published packages or changing source manifests.

Do not delete the existing `~/Cockpit/publishable/local_pub_server/unpub-data`
store or run a broad cache clean. Keep old experiments for comparison or remove
only the specific disposable directory after stopping its server and reviewing
its contents.

Local success is a hosted-protocol and packaging gate, not pub.dev approval.
Finish the normal release checks, provenance checks, CI, archive review, and
manual publication procedure in [Releases](releases.md). GitHub bundle
publication is a separate producer-CI operation; a hosted `dart_wellen` archive
must already contain its runtime and must not rely on that download.
