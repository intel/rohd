# WebAssembly Development Notes

Status as of November 16, 2026: WASM support is **in progress**. The goal is
for all six published ROHD libraries to work in WASM consumers and qualify
for pub.dev's `is:wasm-ready` tag. Rebuilding the separate Live Debugger
Flutter app is not part of this package-readiness work.

## Compilation Versus Package Readiness

Pub distributes Dart source, not a separately compiled WASM package. A
consumer's compiler can omit unused native-only code, so a particular app can
compile and run even when the package is not tagged WASM-ready. Pana checks
the public-library dependency graph for disallowed Dart libraries; a successful
consumer build alone does not establish that the package will receive the tag.

The DevTools app illustrates the distinction. Its
[in-process examples](../rohd_devtools_extension/lib/rohd_devtools/examples/rohd_examples.dart)
record waveforms in memory. It can also read selected waveform bytes through
Wellen, which has its own WASM implementation; this is not ROHD's native
FST writer. A live DevTools client can instead query a separate ROHD process,
which may use FST-backed storage. The checked-in
[DevTools installation build](../tool/gh_actions/devtool/install_devtools.sh)
includes Wellen WASM but does not itself pass Flutter's `--wasm` option.

## Verified So Far

The current checkout's
[web platform test](../test/web_platform_test.dart) passed on the Dart VM,
Chrome with Dart-to-JavaScript, and Chrome with Dart-to-WASM. It exercises
64-bit logic values, simulation, in-memory VCD capture with DevTools streaming,
and in-memory SystemVerilog generation. It also checks that file-backed
waveform capture and source-trace package configuration reads fail explicitly
on the web. These are representative operations, not a test of every public
API or published archive.

```sh
dart test test/web_platform_test.dart --platform vm
dart test test/web_platform_test.dart --platform chrome --compiler dart2js
dart test test/web_platform_test.dart --platform chrome --compiler dart2wasm
```

WASM is a web target, but its integer behavior differs from Dart-to-JavaScript.
[web.dart](../lib/src/utilities/web.dart) distinguishes web detection from
JavaScript integer handling. The package-configuration read in
[source_tracer.dart](../lib/src/utilities/source_tracer.dart) now uses a
conditional native implementation and throws `UnsupportedError` on the web.

### Local Pana Baseline

An initial local Pana 0.23.19 analysis with Dart 3.13.2 was run on November 16,
2026, **before** the source-tracer boundary above was added:

| Package | `platform:web` and `is:wasm-ready` in baseline |
| --- | --- |
| `rohd` | No |
| `rohd_devtools_widgets` | No |
| `rohd_hierarchy` | Yes |
| `rohd_waveform` | Yes |
| `rohd_source_navigator` | Yes |
| `rohd_live_debugger` | Yes |

Pana reported the root library's path to `dart:io` through the source tracer;
the widgets report reached ROHD. The source-tracer change removes that
particular direct import, but other public ROHD paths still use native I/O.
The six analyses have not been repeated against the completed changes, and
this local workspace baseline does not establish the tags of publication
archives or hosted dependency versions. The debugger package's public Dart
library is a marker; its bundled app is a separate artifact.

## Remaining Work

- Audit all public entry points and their transitive platform dependencies.
  Add conditional native boundaries without changing native behavior or
  breaking existing public types. In particular,
  [FstWriter.file](../lib/src/fst/fst_writer.dart) exposes a native
  `RandomAccessFile`.
- Keep in-memory simulation, VCD capture, and synthesis usable in WASM.
  Native-only file operations should remain available but explicitly throw
  `UnsupportedError` on web platforms. Account for current-directory and
  source-tracing paths, not only direct file writes.
- Add focused native and browser tests for each boundary and exercise
  representative public libraries in real WASM consumers. Flutter widgets
  require a Flutter WASM consumer, not a standalone Dart WASM executable.
- Rerun Pana for all six packages and explicitly verify both
  `platform:web` and `is:wasm-ready`. The existing
  [Pana runner](../tool/release/run_pana.sh) checks scores and hosted
  compatibility; it does not currently enforce these tags. Ensure widgets
  resolve the updated ROHD rather than only an older hosted release.
- Verify actual publication archive selection and hosted dependency
  resolution without checkout-local overrides masking failures. Follow the
  [release procedure](releases.md): root ROHD excludes `/packages/`, while
  `check_release.sh` temporarily removes only that ignore rule for nested
  package dry runs and restores it. Dry runs use the real package directories
  and the same archive rules as publication; isolated consumer or Pana
  checks supplement them, not replace them. Do not publish during testing.
