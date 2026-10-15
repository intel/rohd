<!--
Copyright (C) 2026 Intel Corporation
SPDX-License-Identifier: BSD-3-Clause
-->

# Cross-Probing with FLC (File-Line-Column) Traces

ROHD can record the Dart construction site for signals and submodule
instances, then associate those source locations with generated SystemVerilog
or SystemC locations. This supports cross-probing from generated code,
schematics, and the standalone HTML report back to the Dart source.

`SourceTracer` is the tracer used by hardware construction. Activate it before
creating the module hierarchy, and clear it when the tracing session is over.
`TraceService` is the supported API for FLC sidecars and emits the current
FLC v6 format.

## Quick start: SystemVerilog and FLC v6

```dart
import 'dart:io';

import 'package:rohd/rohd.dart';

SourceTracer.activate();

final dut = Top(Logic(name: 'a', width: 8));
await dut.build();

final outputDirectory = 'build/output';
final sv = SystemVerilogService(
  dut,
  multiFile: true,
  register: false,
);
final trace = TraceService(
  dut,
  svService: sv,
  packageRoot: Directory.current.path,
  register: false,
  svOutputMode: SvOutputMode.perModule,
);

sv.writeFiles(outputDirectory);
trace.write(outputDirectory);
trace.writeHtml(outputDirectory);

SourceTracer.clear();
```

This produces one `.sv` file for each generated implementation, a hierarchy
sidecar named `<top-definition>.flc.json`, and an optional
`<top-definition>.flc.html` report. For a single concatenated SystemVerilog
artifact, use the default `SvOutputMode.singleFile` and write the
`SystemVerilogService` output to that file instead.

## Opt-in debugging session

Use `DebugSession` when one debugging session should intentionally combine
source provenance, registered netlist and FLC services, and live DevTools
waveforms:

```dart
final debug = DebugSession.start(
  packageRoot: Directory.current.path,
);

final dut = Top(Logic(name: 'a'));
await dut.build();
debug.attach(dut);

// NetlistService.current and TraceService.current are available to DevTools.
// WaveformDataService is recording live signal changes.

debug.close();
```

`DebugSession.start()` must run before hardware construction; `attach()` must
run after `build()`. `close()` stops the waveform listeners it started,
unregisters its services, and deactivates its tracer. In contrast, constructing
`NetlistService` only registers a netlist; it never starts waveform recording.

## Source-only tracing

Use `SourceTracer` directly to inspect captured construction traces while
debugging:

```dart
SourceTracer.activate();
final dut = Top(Logic());
await dut.build();

final signalTrace = SourceTracer.traceOf(dut, 'internalSignal');
final moduleTraces = SourceTracer.tracesForModule(dut);
final hierarchyTraces = SourceTracer.tracesForHierarchy(dut);

SourceTracer.clear();
```

`SourceTracer.traceJsonForHierarchy` is also available for low-level,
source-only JSON generation. Prefer `TraceService` when a consumer needs
generated-code locations or a sidecar file; it supplies the v6 output files
and line maps automatically.

## FLC v6 structure

`TraceService.flcHierarchy` returns a JSON-serialisable map and `flcJson`
returns the encoded string. The hierarchy has one shared source-file table and
is organized by generated implementation name:

```json
{
  "version": 6,
  "files": [
    "lib/src/top.dart",
    "lib/src/variant.dart"
  ],
  "modules": {
    "Variant_0": {
      "implementationName": "Variant_0",
      "outputFiles": {
        "sv": ["Variant_0.sv"]
      },
      "sourceOccurrences": [
        {
          "path": "top.second",
          "definitionName": "Variant",
          "constructionTrace": ["0:42:5"]
        }
      ],
      "tree": [
        ["1:12:9", "y@sv:4:8"]
      ]
    }
  }
}
```

`files` maps the first component of each source frame
(`fileIndex:line:column`) to a package-relative source path. `tree` is a
trie: every node is `[frame, ...childrenOrSymbols]`, with outer source frames
stored before inner frames.

Leaf symbols use this grammar:

```text
[*]name[@positions][~originalName]
positions := language ":" line ":" column
             (";" language ":" line ":" column)*
```

- `*` identifies a submodule instance.
- `@sv:L:C` and `@sc:L:C` identify generated-code locations.
- `~originalName` preserves a signal name before Namer disambiguation.
- `outputFiles` maps every generated language to a list of artifacts.

### Source occurrences and generated implementations

The `modules` map key is the generated implementation name, not necessarily
the source module's requested `definitionName`. If two source occurrences both
request `Variant` but synthesize differently, ROHD emits `Variant` and
`Variant_0`; FLC records separate module entries, line maps, and output files.

Conversely, equivalent source occurrences can share a single generated
implementation. The implementation entry's `sourceOccurrences` list retains
every source hierarchy path and construction trace, while its `tree` combines
their recorded provenance. This lets a viewer navigate generated code by its
actual implementation and still present every applicable Dart source site.

Use the instance-aware APIs when a requested definition name is ambiguous:

```dart
final occurrenceJson = trace.flcForModuleInstance(dut.subModules.first);
final implementationJson =
    trace.flcModuleJsonForModule(dut.subModules.first);
```

`TraceService.flcForModule(definitionName)` intentionally rejects a definition
name that matches multiple source occurrences so it cannot silently return
the wrong trace.

## SystemC enrichment

Pass a `SystemCService` alongside the SystemVerilog service to include both
languages in the same v6 sidecar:

```dart
final sc = SystemCService(dut, multiFile: true, register: false);
final trace = TraceService(
  dut,
  svService: sv,
  scService: sc,
  packageRoot: Directory.current.path,
  register: false,
  svOutputMode: SvOutputMode.perModule,
  scOutputMode: ScOutputMode.perModule,
);
```

FLC symbols then carry separate `sv:` and `sc:` positions, and
`outputFiles` lists artifacts for both languages.

## Inline SystemVerilog comments

When `SourceTracer` captured traces, `SystemVerilogService` also emits compact
`// ROHD:` comments on traced declarations, assignments, and module
instantiations. The comments use the same `fileIndex:line:column` source-frame
representation as FLC:

```systemverilog
// Source files:
//   0: lib/src/top.dart
assign y = a; // ROHD: 0:24:9
```

The tracer compresses repeated frame suffixes with `^`, `^N`, and `| frame`
markers. FLC v6 sidecars remain the preferred machine-readable format because
they retain output file names, all recorded line positions, and source
occurrence metadata.

## Netlist attributes

`NetlistService` can embed source-only `rohd.src_trace` attributes in Yosys
JSON when configured for tracing:

```dart
final netlist = NetlistService(
  dut,
  configuration: const NetlistSynthesizerConfiguration(trace: true),
  packageRoot: Directory.current.path,
);
print(netlist.toJson());
```

These compact per-module attributes serve netlist consumers. Use a registered
`TraceService` when DevTools or a standalone viewer needs the v6 FLC
hierarchy.

## API summary

| Need | API |
| --- | --- |
| Start or stop capture | `SourceTracer.activate()` / `SourceTracer.clear()` |
| Create a registered netlist | `NetlistService(dut, ...)` |
| Inspect one source trace | `SourceTracer.traceOf(...)` |
| Inspect a source hierarchy | `SourceTracer.tracesForHierarchy(...)` |
| FLC v6 hierarchy or JSON | `TraceService.flcHierarchy` / `TraceService.flcJson` |
| Write FLC v6 | `TraceService.write(...)` |
| Write HTML report | `TraceService.writeHtml(...)` |
| Resolve a source occurrence | `TraceService.flcForModuleInstance(...)` |
| Resolve a generated implementation | `TraceService.flcModuleJsonForModule(...)` |
