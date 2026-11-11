# ROHD 0.7.0 Migration

ROHD 0.7.0 removes long-deprecated and obsolete APIs and completes a few older
breaking renames and merges. Recent deprecations, including `Swizzle`,
`swizzle`, and `rswizzle`, remain available. Migrate affected consumers to the
replacement APIs and release them with a `^0.7.0` core constraint rather than
trying to support both 0.6.x and 0.7.x.

“Deprecated in” gives the first tagged release whose changelog explicitly
records the deprecation. “Not recorded” means the changelog does not identify
the first deprecation release; “N/A” marks an earlier breaking rename or merge
rather than a deprecation.

| Removed API | Deprecated in | Replacement |
| --- | --- | --- |
| `StateMachine` | 0.5.0 | `FiniteStateMachine`, with enum state identifiers |
| `FF` | 0.1.2 | `Sequential` |
| `IfBlock` | 0.5.0 | `If.block` |
| `ExternalModule` | N/A (renamed in 0.2.0) | `ExternalSystemVerilogModule` |
| `LogicValues` | N/A (merged in 0.3.0) | `LogicValue` |
| `Logic.bit` | 0.3.0 | `value`; explicitly check `width == 1` when required |
| `valueInt`, `valueBigInt` | 0.3.0 | `value.toInt()`, `value.toBigInt()` |
| `hasValidValue()`, `isFloating()` on signals | 0.4.2 | `value.isValid`, `value.isFloating` |
| `LogicValue.length`, `LogicValue.bit` | 0.3.0 | `width`, or the value itself with an explicit single-bit width check |
| `LogicValue.fromBool`, `fromInt`, `fromBigInt`, `fromString` | 0.2.0 | `ofBool`, `ofInt`, `ofBigInt`, `ofString` |
| `LogicValue.from(iterable)` | 0.2.0 | `LogicValue.ofIterable(iterable)` |
| Global `concat(signals)`, `rconcat(signals)` | 0.2.0 | `signals.concat()`, `signals.rconcat()` |
| Gate `y` output aliases, including `Add.out` | 0.4.0 | `out`, `Add.sum`, or `Mux.mux`, as appropriate |
| `getReceivers()`, `getDrivers()`, `getConditionals()` | 0.5.0 | `receivers`, `drivers`, `conditionals` |
| `FiniteStateMachine.clk`, `Pipeline.clk` | 0.5.0 | Retain the clock supplied at construction; do not retrieve it from the module |

The following additional deprecated APIs are also removed in 0.7.0.

| Removed API | Replacement | Deprecation / release history |
| --- | --- | --- |
| `Port` | `Logic.port` | Deprecated in 0.6.4 |
| `PairInterface.modify` and its constructor argument | Pass `uniquify` when connecting or adding sub-interfaces | Deprecated in 0.6.7 |
| `PairInterface.clone(other)` | `other.clone()` | Deprecated in 0.6.6 |
| `LogicStructure.bit` | `value`; explicitly check `width == 1` when required | Deprecation release not recorded |
| `Module.unpreferredName`, `Module.isUnpreferred` | `Naming.unpreferredName`, `Naming.isUnpreferred`, or `Logic.naming` | Deprecation release not recorded |
| `Dumper`, `WaveDumper` | `module.dumpWaves(outputPath: ...)` or `WaveformService` | Deprecation release not recorded / released in 0.6.11 |
| `SynthBuilder.top` | `tops` | Deprecation release not recorded |
| `getFileContents()` | `getSynthFileContents()` | Deprecated in 0.6.4 |
| `SynthesisResult.toFileContents()` and older backend overrides | `toSynthFileContents()`; use each artifact's `contents` | Deprecation release not recorded |
| `CustomSystemVerilog` | `SystemVerilog`; combine input/output mappings into the `ports` map of `instantiationVerilog` | Deprecated in 0.6.0 |
| `SystemVerilogSynthesizer.instantiationVerilogWithParameters` | `instantiationVerilogFor` with named arguments and a combined `ports` map | Deprecation release not recorded |
| `Module.generateSynth` | `Module.dumpSystemVerilog` or `SystemVerilogService` | Released without deprecation in 0.6.11 |
| `ModuleTree.hierarchyJSON` | `ModuleTree.hierarchyJson` | Released without deprecation in 0.6.11 |
| `NetlistSynthesisResult.toFileContents()` | `toSynthFileContents()` and each artifact's `contents` | First released, already deprecated, in 0.6.11 |

Compatibility APIs introduced and removed only during unreleased development
are also removed: `FlcService` (use `TraceService`), `SystemCExecutable` (use
`SystemCVectorExecutable`), `ModuleServices.hierarchyJSON` (use `hierarchyJson`),
FLC methods on `NetlistService` (use `TraceService`), and
`SystemVerilogService.contentsByName` (use `instanceTypeOutput` or `fileContents`).

For example, replace `WaveDumper(dut, outputPath: 'waves.vcd')` with
`dut.dumpWaves(outputPath: 'waves.vcd')`. If code needs advanced waveform
options or the resulting service, use `WaveformService` directly. To retain the
old single-string synthesis result, read `toSynthFileContents().single.contents`
only when exactly one artifact is expected; otherwise iterate the artifacts.
