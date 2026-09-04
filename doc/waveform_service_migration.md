# Waveform Service Migration Draft

## Goal
Unify waveform capture with the service model used by `SvService`, `NetlistService`, and `TraceService`, while preserving existing `WaveDumper` behavior during migration.

## Proposed API Surface

### `WaveformFormat`
```dart
enum WaveformFormat {
  vcd,
  fst,
}
```

### `WaveformServiceOptions`
```dart
class WaveformServiceOptions {
  final WaveformFormat format;
  final String outputPath;
  final bool register;
  final String timescale;
  final int flushThresholdChars;
  final bool includeConsts;
  final bool includeInlineSystemVerilog;

  const WaveformServiceOptions({
    this.format = WaveformFormat.vcd,
    this.outputPath = 'waves.vcd',
    this.register = true,
    this.timescale = '1ps',
    this.flushThresholdChars = 100000,
    this.includeConsts = false,
    this.includeInlineSystemVerilog = false,
  });
}
```

### `WaveformService`
```dart
class WaveformService {
  final Module module;
  final WaveformServiceOptions options;

  WaveformService(
    this.module, {
    this.options = const WaveformServiceOptions(),
  });

  String get outputPath;
  bool get isActive;

  Future<void> close();
  Future<void> writeOut();

  Map<String, Object?> toJson();
}
```

## `ModuleServices` integration
Add an opt-in waveform slot and summary getter:

```dart
WaveformService? waveformService;

String get waveformJSON => waveformService != null
    ? jsonEncode(waveformService!.toJson())
    : _unavailable('waveform');
```

## Backward Compatibility Plan

### Keep `WaveDumper`, but make it a compatibility shim
```dart
@Deprecated('Use WaveformService instead.')
class WaveDumper {
  final WaveformService _service;

  WaveDumper(Module module, {String outputPath = 'waves.vcd'})
      : _service = WaveformService(
          module,
          options: WaveformServiceOptions(outputPath: outputPath),
        );
}
```

### Compatibility guarantees
- Existing `WaveDumper(module, outputPath: ...)` call sites keep working.
- Default behavior remains `waves.vcd` in VCD format.
- Existing end-of-simulation write/close semantics are preserved.

## Internal Refactor Strategy

1. Extract reusable internals from `WaveDumper` into private helpers used by both APIs.
2. Keep event hooks (`Simulator.preTick`, end-of-simulation action) behavior-equivalent.
3. Keep signal filtering parity unless explicitly overridden by options.
4. Keep VCD header metadata shape stable unless a format-specific option requires change.

## Rollout Phases

### Phase 1: Introduce new API
- Add `WaveformFormat`, `WaveformServiceOptions`, and `WaveformService`.
- Add `ModuleServices.waveformService` and `waveformJSON`.
- Keep all existing `WaveDumper` behavior unchanged.

### Phase 2: Compatibility shim
- Re-implement `WaveDumper` as a thin wrapper over `WaveformService`.
- Add `@Deprecated` on `WaveDumper` and update docs to prefer `WaveformService`.

### Phase 3: Adoption
- Migrate examples/tests/devtools setup code to `WaveformService`.
- Leave `WaveDumper` in place for at least one release cycle.

### Phase 4: Optional cleanup
- Remove direct internal file-buffer logic from `WaveDumper`.
- Keep only minimal adapter code.

## Test Plan

1. Golden parity tests:
- same input design + same simulation stimuli => same VCD content between old and new API.

2. Lifecycle tests:
- requires built module.
- closes sink at end of simulation.
- handles repeated simulation sessions safely.

3. Registration tests:
- `register=true` sets `ModuleServices.instance.waveformService`.
- `register=false` does not mutate registry.

4. Compatibility tests:
- existing `WaveDumper` tests pass without modifications where practical.

5. Devtools tests:
- service summary is discoverable via `ModuleServices.waveformJSON`.

## Open Questions

1. Should `WaveformService` expose start/stop capture controls, or keep capture always-on after construction?
2. Should format selection be fixed at construction, or allow runtime switch?
3. Should we add per-signal filters now, or defer until after parity migration?
4. Should `WaveformService.writeOut()` be public initially, or only `close()` + auto end-of-sim behavior?

## Recommended First Cut
Keep first cut minimal:
- Constructor semantics.
- Options object with output path and format.
- ModuleServices registration.
- `WaveDumper` shim + deprecation.

This gets service-model consistency quickly while minimizing migration risk.
