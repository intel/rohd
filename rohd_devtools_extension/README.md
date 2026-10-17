# ROHD DevTools Extension

The ROHD DevTools extension provides debugging support for ROHD hardware
designers. It connects to a running Dart VM, reads the ROHD module hierarchy,
and displays live signal information while the debugged program is paused.

Initial proposals and discussions for the devtool can be found at
<https://github.com/intel/rohd/discussions/418>.

For a visual walkthrough of hierarchy navigation, waveforms, schematics,
snapshots, and cross-probing, see
[The ROHD Live Debugger](https://intel.github.io/rohd-website/blog/rohd-live-debugger/).

## Preparing the Program Being Debugged

The debugger UI and the ROHD simulation are separate programs. Opening the UI
does not instrument the simulation: the program being debugged must register
the services it needs after building its top module and before simulation.
Import `package:rohd/rohd.dart` in that program; it does not need to import the
Flutter DevTools application.

Two runnable examples use the same clocked, parallel-load serializer:

| Example | Debugging capabilities | Files written |
| --- | --- | --- |
| [Basic serializer](../example/serializer_debug.dart) | Hierarchy, live values, schematics, and live waveforms | None |
| [Serializer with SystemVerilog](../example/serializer_debug_systemverilog.dart) | All of the above, plus Dart/generated-SystemVerilog source cross-probing | Netlist JSON, SystemVerilog, FLC mapping, and VCD under `build/serializer_debug/` |

These examples use the service APIs in this checkout. Run commands from the
ROHD repository root so package-relative source paths resolve correctly.

### Minimal Setup: Netlist and Live Waveforms

After constructing your design:

```dart
await dut.build();

NetlistService(dut);
WaveformService(dut, enableDevToolsStreaming: true);

// Start simulation and drive your inputs only after registering the services.
```

`NetlistService` supplies hierarchy and schematic connectivity. Its default
`register: true` makes the design discoverable through `NetlistService.current`.
`WaveformService` supplies captured values to `WaveformDataService` when
`enableDevToolsStreaming` is enabled. The default capture is in memory, with
no waveform file written. A waveform file alone does not enable live streaming.
Neither service requires SystemVerilog generation or source tracing.

Run the basic example without a debugger to let the simulation finish:

```sh
dart run example/serializer_debug.dart
```

For an interactive demonstration, open that file in VS Code and start it with
**Run > Start Debugging** (F5), not **Run Without Debugging**. Before starting,
set a breakpoint in
[`simulateSerializer`](../example/serializer/serializer.dart) on
`load.inject(0)`. At each hit, the serializer has loaded the next byte. Set a
breakpoint on the inner loop's `await clk.nextNegedge` to inspect each bit.
The stimulus sends `0xa5`, `0x3c`, and `0x81`, least significant bit first.
The clock period is 10 simulation time units; inputs change on falling edges,
away from the rising-edge register updates.

Attach the UI while paused at one of these breakpoints, **after** service setup.
A pause at program entry is too early: no design has been built yet. Resume
between breakpoints to accumulate waveform history. This short simulation
exits when complete, so do not let it finish before attaching.

### Expanded Setup: SystemVerilog and Source Navigation

The [expanded example](../example/serializer_debug_systemverilog.dart) activates
`SourceTracer` **before constructing any signals or modules**. After `build()`,
it registers the netlist and waveform services and adds:

```dart
final sv = SystemVerilogService(
  dut,
  outputDirectory: outputDirectory,
  multiFile: true,
  embedSourceTraceComments: false,
)..writeOutputs();
TraceService(
  dut,
  svService: sv,
  packageRoot: packageRoot,
  svOutputMode: SvOutputMode.perModule,
).write(outputDirectory);
```

Here `packageRoot` is the absolute package directory and `outputDirectory` is
an absolute directory beneath it. Pass `packageRoot` to `NetlistService` as
well, so its netlist carries the captured Dart source locations.

`SystemVerilogService` writes one `.sv` file per generated implementation.
`TraceService` registers the file-line-column (FLC) mapping between Dart
construction sites and those files. Keep `svOutputMode` consistent with the
generated layout: `perModule` for `multiFile: true`, or `singleFile` for a
concatenated output. Source comments can be disabled without losing line maps.
The example also writes the netlist and a VCD while streaming live waveforms.
Do not set `register: false` on services the live debugger needs to discover.

```sh
dart run example/serializer_debug_systemverilog.dart
```

Use the same VS Code breakpoint workflow as the basic example. Install the
[ROHD VS Code extension](../rohd_extension/README.md) for **Go to Design**
navigation from the browser back into VS Code. It bridges source-navigation
requests over DTD; a direct VM-only connection does not provide that editor
bridge. Keep tracing active while inspecting the design; the example clears it
only after simulation ends.

For SystemC output, the equivalent addition is `SystemCService`, passed as
`scService` to `TraceService`; both generated languages can share one FLC
sidecar. See [SystemC enrichment](../doc/cross_probing.md#systemc-enrichment).
For source tracing and live capture without generated output,
[`DebugSession`](../lib/src/diagnostics/debug_session.dart) is an alternative
bundled lifecycle; use it instead of independently starting the same capture
services. The examples above deliberately show the individual services.

## Opening from Flutter DevTools

The normal user flow is through Flutter DevTools:

1. Start debugging a ROHD program.
2. Stop at a breakpoint or otherwise pause the debugged program.
3. Use **Open DevTools in Browser** from VS Code.
4. In the browser DevTools page, open the **ROHD** tab.

If prompted, enable the ROHD extension for the connected application. Start
with a breakpoint after the service setup described above. Select `serializer`
in the Module Tree, inspect `clk`, `reset`, `load`, `parallelData`, and
`serialOut` in Details, then send signals to Waveform or Schematic. Resume to
the next breakpoint to see the next simulation state. The UI's pause-tracking
control freezes display refreshes; it does not pause the Dart simulation.

See the Flutter DevTools documentation for the surrounding DevTools workflow:
<https://docs.flutter.dev/tools/devtools>.

When opened this way, the extension runs inside Flutter DevTools and uses VS
Code's Dart Tooling Daemon (DTD) integration to attach to and control the
debugged Dart VM.

## Opening the Hosted Web Debugger

You can use the standalone
[ROHD Live Debugger](https://intel.github.io/rohd/rohd-live-debugger/)
without building the Flutter application locally:

1. Start a VS Code debug session for your instrumented ROHD program and pause
   after service setup.
2. Copy the **DTD URI** for that VS Code session. With the ROHD VS Code
   extension installed, the Debug Console banner lists `DTD: URI` and offers a
   **Copy** notification. For remote sessions, use the forwarded URI when one
   is listed.
3. Open the web debugger and its connection form (the connection/chain-link
   icon). Paste the URI into **DTD URI (auto-discover VMs)** and click
   **Discover**.
4. Select the Dart VM for your simulation, then connect. DTD can expose
   multiple debug sessions; choose the one containing your design.
5. Inspect the paused design and resume/step it using VS Code's debug controls.

The DTD URI and VM service URI are different addresses. DTD discovers available
VMs and supports the editor bridge; the VM service connects to one specific
simulation. The standalone form also accepts a VM service URI directly.
For a terminal-launched simulation, start with the VM service enabled:

```sh
dart run --observe --pause-isolates-on-start example/serializer_debug.dart
```

Copy the VM service URI printed by Dart, not its DevTools browser URL.
Connect to that VM and use Dart DevTools' debugger to set a breakpoint in the
stimulus and resume past entry; the ROHD services are not available until the
setup code has executed. Terminal-only attachment does not create VS Code's
DTD or its source-navigation bridge.

The browser must be able to reach the supplied WebSocket addresses. For SSH,
containers, or other remote development, forward the DTD and selected VM
service ports as needed. If browser HTTPS/WebSocket restrictions block the
connection, use the locally served or native standalone form below. Treat
both URIs as access credentials and do not publish them.

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
tool/gh_actions/build_app.sh /rohd/rohd-live-debugger/
```

The bundle is written to `build/web/`. The optional argument must start and end
with `/`; it becomes the Flutter base href used when the app is hosted below a
site root. When the argument is omitted in GitHub Actions, the repository name
determines the base href. Local builds default to `/rohd_devtools_extension/`.
The build disables Flutter's generated service worker to avoid stale bundles.
On pushes to `main`, the `General` workflow includes this bundle in the existing
ROHD documentation deployment at
[`https://intel.github.io/rohd/rohd-live-debugger/`](https://intel.github.io/rohd/rohd-live-debugger/).

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

The dependency tasks configure four independent bundles: ROHD core, ROHD
companion packages, the Wave Viewer, and the Schematic Viewer. Each bundle can
use hosted, Git, or local packages without changing the other bundles. The
selection is persisted in the ignored `.devtools_dependency_sources` file and
rendered into `pubspec_overrides.yaml` by
[`scripts/devtools_dev_mode.sh`](scripts/devtools_dev_mode.sh). Local viewer
paths default below `~/true-release` when that directory exists and otherwise
below `~/release`; the task prompts and script environment variables can
override those defaults. The web application loads Schematic Viewer assets
through Flutter's package asset namespace, so hosted Schematic Viewer builds
do not require a local viewer checkout.

### CI Local-Package Smoke Test

The DevTools CI jobs run
[`tool/gh_actions/write_local_package_overrides.sh`](../tool/gh_actions/write_local_package_overrides.sh)
before resolving dependencies. In a clean checkout this creates the ignored
`pubspec_overrides.yaml` with relative paths to ROHD and the companion packages
that are released from this repository: `rohd_hierarchy`, `rohd_waveform`,
`rohd_devtools_widgets`, and `rohd_source_navigator`.

Both the extension test and web-build commands run
[`tool/verify_local_package_resolution.dart`](tool/verify_local_package_resolution.dart)
immediately after `flutter pub get`. It fails unless
`.dart_tool/package_config.json` resolves every one of those packages to the
current checkout.

The pull-request and artifact workflows run
[`tool/gh_actions/devtool/smoke_test_local_packages.sh`](../tool/gh_actions/devtool/smoke_test_local_packages.sh).
That smoke test performs the production `flutter build web` and then asks the
real DevTools extension loader to discover the generated artifact. It requires
no DTD session and no widget test: a successful build proves that the
extension's production dependency graph compiles against the exact ROHD source
being released, and discovery verifies that the output is installable.

## Command-Line Interface

The supported terminal entrypoint is the DTD-attached shell in
[`bin/rohd_shell.dart`](bin/rohd_shell.dart). It currently provides target
hierarchy and connectivity queries, and it can send selected signals to
available DevTools or VS Code cross-probe participants. The intended DevTools
CLI architecture is a generic command host whose connectivity, waveform, and
future providers register their capabilities rather than expose separate
tool-specific executables.

The older `rohd-wave` implementation was a waveform-specific prototype, not
the DevTools CLI and not a supported packaged executable. Its waveform commands
have not yet moved into the generic command host. Do not use `make cli-build`
or publish `build/cli/rohd-wave` as the DevTools command-line interface.

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
flutter test --platform chrome $(
  find test -type f -name '*_test.dart' ! -path 'test/debugger/*' | sort
)
```

Core debugger-service tests run on the Dart VM because they construct ROHD
hardware and drive the simulator:

```sh
flutter test test/debugger/
```
