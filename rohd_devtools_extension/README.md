# ROHD DevTools Extension

The ROHD DevTools extension provides debugging support for ROHD hardware
designers. It connects to a running Dart VM, reads the ROHD module hierarchy,
and displays live signal information while the debugged program is paused.

Initial proposals and discussions for the devtool can be found at
<https://github.com/intel/rohd/discussions/418>.

## Opening from Flutter DevTools

The normal user flow is through Flutter DevTools:

1. Start debugging a ROHD program.
2. Stop at a breakpoint or otherwise pause the debugged program.
3. Use **Open DevTools in Browser** from VS Code.
4. In the browser DevTools page, open the **ROHD** tab.

See the Flutter DevTools documentation for the surrounding DevTools workflow:
<https://docs.flutter.dev/tools/devtools>.

When opened this way, the extension runs inside Flutter DevTools and uses VS
Code's Dart Tooling Daemon (DTD) integration to attach to and control the
debugged Dart VM.

## Standalone Release Mode

The extension can also run as a standalone app. This is useful when you want to
connect directly to a Dart VM service URI, discover running VMs through a DTD
URI from the app's connection form, and select the specific debug VM to which to
attach.

Run the release web standalone form:

```sh
cd rohd_devtools_extension
flutter run --release -d web-server --web-port=9099 --web-hostname=0.0.0.0 lib/main_standalone.dart
```

Build a static bundle for a repository-scoped web path:

```sh
cd rohd_devtools_extension
tool/gh_actions/build_app.sh /rohd/rohd_devtools_extension/
```

The bundle is written to `build/web/`. The optional argument must start and end
with `/`; it becomes the Flutter base href used when the app is hosted below a
site root. When the argument is omitted in GitHub Actions, the repository name
determines the base href. Local builds default to `/rohd_devtools_extension/`.
The build disables Flutter's generated service worker to avoid stale bundles.
On pushes to `main`, the `General` workflow includes this bundle in the existing
ROHD documentation deployment at `/rohd_devtools_extension/`.

Run the release Linux standalone form:

```sh
cd rohd_devtools_extension
flutter run --release -d linux lib/main_standalone.dart
```

If the Linux build needs software rendering, use:

```sh
cd rohd_devtools_extension
flutter run --release -d linux --enable-software-rendering lib/main_standalone.dart
```

The repository's `.vscode/tasks.json` contains development utilities for these
flows, including debug-mode variants. Those VS Code tasks are for extension
development only and may change or be removed; the commands above are the
release-mode forms to use directly.

## Command-Line Interface

The supported terminal entrypoint is the DTD-attached shell in
[`bin/rohd_shell.dart`](bin/rohd_shell.dart). It currently provides target
hierarchy and connectivity queries, and it can send selected signals to
available DevTools or VS Code cross-probe participants. The intended DevTools
CLI architecture is a generic command host whose connectivity, waveform, and
future providers register their capabilities rather than expose separate
tool-specific executables.

The older `rohd-wave` implementation in [`bin/rohd_wave.dart`](bin/rohd_wave.dart)
is a waveform-specific prototype, not the DevTools CLI and not a supported
packaged executable. Its waveform commands have not yet moved into the generic
command host. Do not use `make cli-build` or publish
`build/cli/rohd-wave` as the DevTools command-line interface.

### Handle Queries

The DevTools console query core uses typed signal handles rather than requiring
people to repeatedly type compact addresses. Its supported language is small:
select a signal, bind it with `let`, then pipe that signal to one graph query.

```text
let mid = select signal top/mid
@mid | fanout
@mid | fanin
select signal top/a | fanout transparent
select signal 0.2.4 | fanout
```

`@mid` retains the signal's canonical path, leaf name, width, and stable
address. The default `fanin` and `fanout` stages take one horizontal net hop.
`fanout transparent` follows an encountered input port into its non-leaf child
block, repeating until it reaches ports on leaf blocks. This makes a signal
cross module boundaries without pretending that arbitrary logic is a
pass-through. It does not traverse through primitive cells or infer cones
through muxes, adders, or flops; those need separate, explicit policies.

### DTD Shell Attachment

`rohd_shell.dart` is a DTD-attached inspection shell. It first uses the
DevTools-owned `rohd.devtoolsShell` service when that service is registered.
Otherwise it discovers the Dart VM through DTD and evaluates
`RohdShellService` in the paused target isolate. The target fallback requires
no DevTools browser or running service extension after target discovery.

The target must construct a registered `NetlistService`; shell hierarchy and
connectivity queries are unavailable when the target has only legacy
`ModuleTree` JSON.

```sh
dart run bin/rohd_shell.dart --dtd "$DTD_URI"
dart run bin/rohd_shell.dart --dtd "$DTD_URI" top
dart run bin/rohd_shell.dart --dtd "$DTD_URI" 'find-signals "clk|reset"'
```

The first form starts an interactive session. The later forms send one command
and print a JSON response. Use `help` in the shell for manifest-derived command
help and argument metadata.

#### Cross-Probe Send

`send` is an agent operation: it resolves signal paths in the shell process
that owns the live occurrence handles, then publishes only canonical paths to
an available cross-probe participant. Occurrence wrappers never cross the DTD
or VS Code boundary.

```text
let sum = find-signal top/alu/sum
send $sum top/clk
```

When the terminal is using `rohd.devtoolsShell`, `send` uses DevTools' local
`CrossProbeService`; both `$sum` and the established `@sum` alias spelling are
accepted there. When the terminal is using the target fallback and the VS Code
extension is connected, it resolves each reference with the target shell and
calls the `rohd.signalBus.send` DTD service. That service delegates to
`rohd.sendSignals`, so registered VS Code viewers receive the same canonical
path list even when DevTools is not running.

`send` reports an unavailable capability when no suitable signal bus is
registered. It accepts signals only; focusing cells is a separate capability.

#### Hierarchy and Connectivity Commands

Paths are absolute and use `/` (for example, `top/alu/sum`); dot-separated
paths are accepted as input too. `find-cell` and `find-signal` return live
target objects, so a shell alias retains identity instead of serializing and
re-parsing the occurrence.

```text
top
find-cell <cell-path>
find-signal <signal-path>
find-cells <regex> [root=. ] [opaque|transparent]
find-signals <regex> [root=. ] [opaque|transparent]
owner-cell <signal-path-or-alias>
parent-cell <cell-path-or-alias>
fanin <signal-path-or-alias> [opaque|transparent]
fanout <signal-path-or-alias> [opaque|transparent]

let sum = find-signal top/alu/sum
fanin $sum transparent
send $sum top/clk
let leaves = find-cells '.*' . transparent
```

The default root for `find-cells` and `find-signals` is `.` (the top
occurrence). Regexes match occurrence or signal names within that root's
subtree. `opaque` searches every descendant and returns immediate connectivity
endpoints. `transparent` returns only leaf cells/signals for searches, and for
fanin/fanout it crosses only hierarchical port boundaries until it reaches a
leaf. It never infers propagation through arbitrary logic, primitives, muxes,
adders, or flops. Invalid regexes and unknown paths produce JSON error
responses.

#### Current Scope and Next Work

The current shell supports structural hierarchy lookup, regex querying,
ownership, and netlist-backed port connectivity. Remaining work includes:

- Clear shell aliases when the registered `NetlistService` changes, so stale
live occurrences cannot cross designs.
- Add broader connectivity fixtures for buses, inouts, constants, multiple
drivers, and fanin/fanout parity with the schematic graph implementation.
- Add optional query limits and pagination to keep large-design regex and
connectivity responses bounded.
- Attach the existing schematic graph through `externalHierarchy` when a
shared target-side graph API is needed, preserving the same occurrence
handles.
- Add waveform-value and source-location commands backed by
`WaveformDataService` and `TraceService`; report those capabilities as
unavailable until their services are initialized.

Shell argument and command validation errors exit with code `64`. Operational
errors, including an unavailable DTD or VM, exit with code `1`.

## Current Features

The in-app help menu is the source of truth for the current feature set. The
main capability today is module-level inspection:

- Select a block from the Module Tree.
- View that module's live port and internal `Logic` values in the Details pane.
- Search and filter the Module Tree and signal list.
- Refresh the module hierarchy from the connected VM.
- Export the signal details table as a PNG.

## Contributions

We welcome contributions to the development of the ROHD DevTools extension.
Please refer to the contributing documentation for guidance on how to get
started.

## Running Tests

The ROHD DevTools extension runs in an iframe when embedded in DevTools, so use
the Chrome platform for browser-based widget tests.

```sh
flutter test --platform chrome test/
```
