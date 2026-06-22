// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemc_cosim_ffi.dart
// FFI-based real-time co-simulation with a SystemC compiled module.
//
// 2026 May
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/systemc/systemc_synthesis_result.dart';
import 'package:rohd/src/utilities/synchronous_propagator.dart';
import 'package:rohd/src/utilities/web.dart';

// ============================================================================
// FFI Type Definitions (using only dart:ffi built-in types)
// ============================================================================

typedef _DestroyDart = void Function(Pointer<Void>);

typedef _SetInputDart = void Function(Pointer<Void>, Pointer<Char>, int);

typedef _SetInputWideDart = void Function(
    Pointer<Void>, Pointer<Char>, Pointer<Char>);

typedef _GetOutputDart = int Function(Pointer<Void>, Pointer<Char>);

typedef _GetOutputWideDart = Pointer<Char> Function(
    Pointer<Void>, Pointer<Char>);

typedef _AdvanceDart = void Function(Pointer<Void>, int);

// ============================================================================
// SystemCFfiCosim — Real-time FFI co-simulation with SystemC
// ============================================================================

/// A co-simulation wrapper that compiles an ROHD module's SystemC output to a
/// shared library and drives it in lock-step with the ROHD [Simulator].
///
/// ## How it works
///
/// 1. The ROHD module is synthesized to SystemC C++ via
///    [Module.generateSystemC]
/// 2. A C-linkage FFI wrapper is generated around the SystemC module
/// 3. The wrapper is compiled to a `.so` shared library
/// 4. On each [Simulator] tick (at the `clkStable` phase):
///    - Current ROHD input values are pushed to SystemC via FFI
///    - SystemC is advanced by one half clock period (`sc_start`)
///    - SystemC output values are pulled back and `put()` onto ROHD outputs
///
/// ## Timing compatibility with existing tests
///
/// The synchronization point at `clkStable` means:
/// - `inject()` calls have already executed (mainTick phase)
/// - Clock has already toggled (mainTick)
/// - `previousValue` was snapshot at preTick (before this tick started)
/// - After clkStable, outputs are updated, then `postTick` fires
/// - `await clk.nextPosedge` resumes after postTick
///
/// This preserves the same timing semantics as native ROHD Sequential blocks.
///
/// ## Example
///
/// ```dart
/// final counter = SimpleCounter(clk, reset, en);
/// await counter.build();
///
/// final cosim = await SystemCFfiCosim.create(counter, clk: clk);
/// if (cosim == null) return; // SystemC not installed
///
/// // Now run your test exactly as before:
/// unawaited(Simulator.run());
/// reset.inject(1);
/// await clk.nextPosedge;
/// // ... counter.output('val') is driven by SystemC
/// ```
class SystemCFfiCosim {
  /// The ROHD module whose SystemC synthesis is being co-simulated.
  final Module module;

  /// The clock signal (null for combinational/clockless mode).
  final Logic? clk;

  /// Clock period in nanoseconds (matches SimpleClockGenerator's period).
  /// Ignored in combinational mode.
  final int clockPeriodNs;

  /// Whether this cosim operates in combinational (clockless) mode.
  /// In this mode, inputs are propagated immediately via delta cycles
  /// (sc_start(SC_ZERO_TIME)) whenever any input changes.
  bool get isCombinational => clk == null;

  /// Handle to the loaded shared library.
  DynamicLibrary? _lib;

  /// Opaque handle to the SystemC simulation context.
  Pointer<Void> _handle = nullptr;

  /// Path to the compiled .so file.
  late String? _soPath;

  /// Input port names and widths.
  final Map<String, int> _inputWidths = {};

  /// Output port names and widths.
  final Map<String, int> _outputWidths = {};

  /// Clock port name(s) to skip when driving inputs.
  final Set<String> _clockNames = {};

  /// Whether the cosim is actively stepping.
  bool _active = false;

  /// Subscription to Simulator.clkStable for per-tick stepping (clocked mode).
  StreamSubscription<void>? _clkStableSubscription;

  /// Synchronous subscriptions on input glitches (combinational mode).
  final List<SynchronousSubscription<LogicValueChanged>>
      _inputGlitchSubscriptions = [];

  /// Whether a combinational step is already pending in this propagation wave.
  /// Prevents re-entrant stepping when multiple inputs change in the same
  /// event (e.g. Swizzle feeding a bus).
  bool _combStepPending = false;

  // FFI function handles
  late final _SetInputDart _setInput;
  late final _SetInputWideDart _setInputWide;
  late final _GetOutputDart _getOutput;
  late final _GetOutputWideDart _getOutputWide;
  late final _AdvanceDart _advance;
  late final _DestroyDart _destroy;

  // Cached C-string pointers for signal names (allocated once, reused every
  // step)
  final Map<String, Pointer<Void>> _inputNamePtrs = {};
  final Map<String, Pointer<Void>> _outputNamePtrs = {};

  // Cached signal references (avoid module.input/output map lookups per step)
  final Map<String, Logic> _inputSignals = {};
  final Map<String, Logic> _outputSignals = {};

  // Pre-allocated buffer for wide hex strings (avoids malloc/free per step).
  // 512 chars covers up to 2048-bit signals.
  Pointer<Void> _hexBuf = nullptr;
  static const _hexBufSize = 512;

  // Native memory management
  static final _free = DynamicLibrary.process().lookupFunction<
      Void Function(Pointer<Void>), void Function(Pointer<Void>)>('free');
  static final _malloc = DynamicLibrary.process().lookupFunction<
      Pointer<Void> Function(IntPtr), Pointer<Void> Function(int)>('malloc');

  /// Cache of loaded libraries and handles keyed by .so path.
  /// Prevents re-loading a .so that's already in the process, which
  /// would crash SystemC's singleton kernel (E113).
  static final _loadedLibs = <String, _LoadedCosimLib>{};

  /// Deletes all `cosim_ffi_*` source and shared-library files from
  /// `tmp_test/` and clears the in-process cache.
  ///
  /// Call from `tearDownAll` in tests to satisfy `check_tmp_test.sh`.
  static void cleanupCache() {
    _loadedLibs.clear();
    const dir = 'tmp_test';
    final d = Directory(dir);
    if (!d.existsSync()) {
      return;
    }
    for (final entity in d.listSync()) {
      final name = entity.uri.pathSegments.last;
      if (name.startsWith('cosim_ffi_') || name.startsWith('libcosim_ffi_')) {
        try {
          entity.deleteSync(recursive: true);
        } on Exception catch (_) {
          // ignore deletion errors (file may be locked or already removed)
        }
      }
    }
  }

  SystemCFfiCosim._(this.module, this.clk, {required this.clockPeriodNs});

  /// Compiles the module's SystemC output to a shared library, loads it,
  /// and begins co-simulation.
  ///
  /// Returns `null` if SystemC is not installed or compilation fails.
  ///
  /// If [clk] is provided, the cosim operates in clocked mode — stepping
  /// SystemC at each clock edge via `Simulator.clkStable`.
  ///
  /// If [clk] is omitted (null), the cosim operates in combinational mode —
  /// propagating inputs through SystemC delta cycles immediately whenever
  /// any input signal changes. This gives the same semantics as native ROHD
  /// [Combinational] blocks.
  static Future<SystemCFfiCosim?> create(
    Module module, {
    Logic? clk,
    int clockPeriodNs = 10,
    String? systemcHome,
    String? systemcLib,
  }) async {
    if (kIsWeb) {
      return null;
    }

    final cosim = SystemCFfiCosim._(module, clk, clockPeriodNs: clockPeriodNs);

    if (!cosim._compileAndLoad(
      systemcHome: systemcHome ?? '',
      systemcLib: systemcLib ?? '',
    )) {
      return null;
    }

    cosim
      .._cachePortInfo()
      .._start();
    return cosim;
  }

  /// Pre-elaborates the module's SystemC code without starting co-simulation.
  ///
  /// Call this in `setUpAll` for every module configuration that will be
  /// cosim-tested in the file. This ensures all SystemC module types are
  /// instantiated during the elaboration phase (before `sc_start`), which
  /// avoids E113 errors when multiple configurations are tested.
  ///
  /// Returns `false` if SystemC is not installed or compilation fails.
  static Future<bool> preElaborate(
    Module module, {
    Logic? clk,
    int clockPeriodNs = 10,
    String? systemcHome,
    String? systemcLib,
  }) async {
    if (kIsWeb) {
      return false;
    }

    final cosim = SystemCFfiCosim._(module, clk, clockPeriodNs: clockPeriodNs);

    return cosim._compileAndLoad(
      systemcHome: systemcHome ?? '',
      systemcLib: systemcLib ?? '',
    );
  }

  /// Compiles the SystemC wrapper to .so and loads it.
  /// Uses a static cache to avoid re-loading the same .so (which would
  /// crash SystemC's singleton kernel with E113).
  bool _compileAndLoad({
    required String systemcHome,
    required String systemcLib,
  }) {
    final resolvedHome = _resolveHome(systemcHome);
    final resolvedLib = _resolveLib(systemcLib);
    if (resolvedHome == null || resolvedLib == null) {
      // ignore: avoid_print
      print('SystemC FFI cosim: SystemC installation not found');
      return false;
    }

    // Collect port widths — treat clocks as regular 1-bit inputs driven
    // manually via sc_signal<bool> (avoids sc_clock phase alignment issues
    // when reusing the cached SystemC kernel across tests).
    for (final entry in module.inputs.entries) {
      final name = entry.key;
      if (name == 'clk' || name.contains('clock')) {
        _clockNames.add(name);
      }
      _inputWidths[name] = entry.value.width;
    }
    for (final entry in module.outputs.entries) {
      _outputWidths[entry.key] = entry.value.width;
    }

    // Generate wrapper C++ source
    final generatedSC = module.generateSystemC();

    // Compute a content hash to distinguish modules with the same
    // definitionName but different logic (e.g., DAZ/FTZ variants).
    // Strip non-deterministic lines (e.g. timestamps) before hashing so
    // that repeated instantiations of the same module share one .so.
    final stableCode = generatedSC
        .split('\n')
        .where((line) => !line.contains('Generation time:'))
        .join('\n');
    final contentHash = stableCode.hashCode.toUnsigned(32).toRadixString(16);
    final uniqueName = '${module.definitionName}_$contentHash';

    // Rename the top-level SC_MODULE in the generated code to the unique name
    // so that different logic variants don't collide in the SystemC linker.
    final renamedSC = generatedSC.replaceAll(module.definitionName, uniqueName);
    final wrapperSrc = _generateWrapper(renamedSC, uniqueName);

    const dir = 'tmp_test';
    Directory(dir).createSync(recursive: true);
    final cacheKey = uniqueName;
    final cppFile = '$dir/cosim_ffi_$cacheKey.cpp';
    _soPath = '$dir/libcosim_ffi_$cacheKey.so';

    // Check cache — if already loaded in this process, reuse it
    if (_loadedLibs.containsKey(cacheKey)) {
      final cached = _loadedLibs[cacheKey]!;
      _lib = cached.lib;
      _handle = cached.handle;
      _setInput = cached.setInput;
      _setInputWide = cached.setInputWide;
      _getOutput = cached.getOutput;
      _getOutputWide = cached.getOutputWide;
      _advance = cached.advance;
      _destroy = cached.destroy;

      // Reset all inputs to 0 (including clock) so the DUT starts fresh.
      // The writes are committed by the first sc_start in _step().
      // Note: _cachePortInfo() is called after this, so use temp pointers here.
      for (final name in _inputWidths.keys) {
        if (_inputNamePtrs.containsKey(name)) {
          _setInput(_handle, _inputNamePtrs[name]!.cast(), 0);
        } else {
          final namePtr = _toCString(name);
          _setInput(_handle, namePtr.cast(), 0);
          _free(namePtr);
        }
      }

      return true;
    }

    // Compile (only if .so doesn't exist on disk)
    if (!File(_soPath!).existsSync()) {
      File(cppFile).writeAsStringSync(wrapperSrc);

      final cxxStd = _detectCxxStd(resolvedLib);
      final result = Process.runSync('g++', [
        '-std=$cxxStd',
        '-shared',
        '-fPIC',
        '-O2',
        '-I$resolvedHome',
        '-L$resolvedLib',
        '-Wl,-rpath,$resolvedLib',
        '-o',
        _soPath!,
        cppFile,
        '-lsystemc',
      ]);

      if (result.exitCode != 0) {
        // ignore: avoid_print
        print('SystemC FFI: compilation failed:\n${result.stderr}');
        return false;
      }
    }

    // Load the shared library
    _lib = DynamicLibrary.open(_soPath!);

    // Bind function pointers
    final create = _lib!.lookupFunction<Pointer<Void> Function(Pointer<Char>),
        Pointer<Void> Function(Pointer<Char>)>('sc_cosim_create');
    _setInput = _lib!.lookupFunction<
        Void Function(Pointer<Void>, Pointer<Char>, Uint64),
        _SetInputDart>('sc_cosim_set_input');
    _setInputWide = _lib!.lookupFunction<
        Void Function(Pointer<Void>, Pointer<Char>, Pointer<Char>),
        _SetInputWideDart>('sc_cosim_set_input_wide');
    _getOutput = _lib!.lookupFunction<
        Uint64 Function(Pointer<Void>, Pointer<Char>),
        _GetOutputDart>('sc_cosim_get_output');
    _getOutputWide = _lib!.lookupFunction<
        Pointer<Char> Function(Pointer<Void>, Pointer<Char>),
        _GetOutputWideDart>('sc_cosim_get_output_wide');
    _advance = _lib!
        .lookupFunction<Void Function(Pointer<Void>, Uint64), _AdvanceDart>(
            'sc_cosim_advance');
    _destroy = _lib!.lookupFunction<Void Function(Pointer<Void>), _DestroyDart>(
        'sc_cosim_destroy');

    // Create the SystemC context (elaborates the design)
    final namePtr = _toCString(module.definitionName);
    _handle = create(namePtr.cast());
    _free(namePtr);

    if (_handle == nullptr) {
      // ignore: avoid_print
      print('SystemC FFI: sc_cosim_create returned null');
      return false;
    }

    // Cache for reuse
    _loadedLibs[cacheKey] = _LoadedCosimLib(
      lib: _lib!,
      handle: _handle,
      setInput: _setInput,
      setInputWide: _setInputWide,
      getOutput: _getOutput,
      getOutputWide: _getOutputWide,
      advance: _advance,
      destroy: _destroy,
    );

    return true;
  }

  /// Pre-allocates cached C-string pointers and signal references.
  /// Call once after _compileAndLoad succeeds.
  void _cachePortInfo() {
    for (final entry in _inputWidths.entries) {
      _inputNamePtrs[entry.key] = _toCString(entry.key);
      _inputSignals[entry.key] = module.input(entry.key);
    }
    for (final entry in _outputWidths.entries) {
      _outputNamePtrs[entry.key] = _toCString(entry.key);
      _outputSignals[entry.key] = module.output(entry.key);
    }
    // Pre-allocate hex buffer for wide signals
    _hexBuf = _malloc(_hexBufSize);
  }

  /// Whether an edge occurred in this tick (set by glitch listener).
  bool _edgePending = false;

  /// Subscription to clock glitch for edge detection.
  SynchronousSubscription<LogicValueChanged>? _glitchSubscription;

  /// Starts the co-simulation by hooking into the clock's glitch and
  /// Simulator.clkStable — mirroring how ROHD's Sequential works.
  ///
  /// In clocked mode: Steps SystemC on BOTH posedge and negedge, advancing
  /// by half-period each time. This keeps the SystemC clock perfectly aligned
  /// with ROHD's:
  ///
  ///   ROHD posedge  → sc_start(T/2) → SystemC posedge occurs → read outputs
  ///   ROHD negedge  → sc_start(T/2) → SystemC negedge occurs → read outputs
  ///
  /// In combinational mode: Listens to input signal glitches and immediately
  /// propagates through SystemC via delta cycles (sc_start(0)). This gives
  /// the same timing semantics as native ROHD [Combinational] blocks.
  void _start() {
    _active = true;

    if (isCombinational) {
      _startCombinational();
    } else {
      _startClocked();
    }
  }

  /// Starts clocked mode — step at each clock edge via clkStable.
  void _startClocked() {
    // Detect any clock edge (0→1 or 1→0) by listening to the glitch stream.
    _glitchSubscription = clk!.glitch.listen((event) {
      if (!_active) {
        return;
      }
      // Any valid transition on the clock (posedge or negedge)
      final isPosedge = event.previousValue == LogicValue.zero &&
          event.newValue == LogicValue.one;
      final isNegedge = event.previousValue == LogicValue.one &&
          event.newValue == LogicValue.zero;
      if ((isPosedge || isNegedge) && !_edgePending) {
        _edgePending = true;
        // Wait for clkStable (all inputs settled) then step SystemC.
        unawaited(Simulator.clkStable.first.then((_) {
          if (!_active) {
            return;
          }
          _edgePending = false;
          _step();
        }));
      }
    });
  }

  /// Starts combinational mode — step on any input change (synchronous).
  ///
  /// Uses synchronous glitch subscriptions so that output values are
  /// available immediately after `put()` — matching native ROHD behavior.
  ///
  /// Does NOT call sc_start here — the kernel transition from ELABORATION
  /// to RUNNING is deferred to the first actual `_stepCombinational()` call.
  /// This allows multiple module variants to be pre-elaborated before the
  /// kernel starts (avoiding E113 errors).
  void _startCombinational() {
    for (final entry in _inputWidths.entries) {
      final name = entry.key;
      // Skip clock-like signals (shouldn't exist in combinational mode,
      // but guard against it)
      if (_clockNames.contains(name)) {
        continue;
      }

      final signal = module.input(name);
      final sub = signal.glitch.listen((event) {
        if (!_active) {
          return;
        }
        if (_combStepPending) {
          return;
        }
        _combStepPending = true;

        // Push all current inputs, advance by 1 ps (triggers delta cycles),
        // and pull outputs. The _combStepPending flag prevents re-entrant
        // calls during the same propagation wave.
        _stepCombinational();
        _combStepPending = false;
      });
      _inputGlitchSubscriptions.add(sub);
    }
  }

  /// One co-simulation step: push inputs, advance time, pull outputs.
  void _step() {
    _pushInputs();

    // Advance SystemC to process the signal writes (delta cycle).
    // We advance T/2 per edge for timing consistency. The clock signal
    // is driven manually (not sc_clock), so posedge/negedge detection
    // in SystemC relies on the sc_signal<bool> transitions we just wrote.
    _advance(_handle, clockPeriodNs * 1000 ~/ 2);

    _pullOutputs();
  }

  /// Combinational step: push inputs, advance minimally, pull outputs.
  ///
  /// Advances by 1 ps — the minimum non-zero time to trigger the full
  /// SystemC evaluate→update→notify loop. Per IEEE 1666 §4.3.4.2,
  /// sc_start(SC_ZERO_TIME) explicitly does NOT process delta notifications,
  /// so external signal writes cannot trigger SC_METHOD evaluation without
  /// a non-zero time advancement.
  void _stepCombinational() {
    _pushInputs();
    _advance(_handle, 1); // 1 ps — minimum to trigger full eval loop
    _pullOutputs();
  }

  /// Pushes all current ROHD input values to the SystemC model via FFI.
  void _pushInputs() {
    for (final entry in _inputWidths.entries) {
      final name = entry.key;
      final width = entry.value;
      final signal = _inputSignals[name]!;
      final val = signal.value;

      if (width <= 64) {
        final intVal = val.isValid ? val.toInt() : 0;
        _setInput(_handle, _inputNamePtrs[name]!.cast(), intVal);
      } else {
        final bigVal =
            val.isValid ? val.toBigInt().toUnsigned(width) : BigInt.zero;
        var hex = bigVal.toRadixString(16);
        if (hex.length.isOdd) {
          hex = '0$hex';
        }
        // Write hex into pre-allocated buffer (no malloc/free per step)
        final fullHex = '0x$hex';
        final bytes = utf8.encode(fullHex);
        final buf = _hexBuf.cast<Uint8>();
        for (var i = 0; i < bytes.length && i < _hexBufSize - 1; i++) {
          (buf + i).value = bytes[i];
        }
        (buf + bytes.length).value = 0;
        _setInputWide(_handle, _inputNamePtrs[name]!.cast(), _hexBuf.cast());
      }
    }
  }

  /// Pulls all SystemC output values back to ROHD signals.
  void _pullOutputs() {
    for (final entry in _outputWidths.entries) {
      final name = entry.key;
      final width = entry.value;
      final signal = _outputSignals[name]!;

      if (width <= 64) {
        final intVal = _getOutput(_handle, _outputNamePtrs[name]!.cast());
        signal.put(LogicValue.ofInt(intVal, width));
      } else {
        final hexCharPtr =
            _getOutputWide(_handle, _outputNamePtrs[name]!.cast());
        final hexStr = _fromCString(hexCharPtr);
        final bigVal = BigInt.parse(
            hexStr.startsWith('0x') ? hexStr.substring(2) : hexStr,
            radix: 16);
        signal.put(LogicValue.of(bigVal.toUnsigned(width), width: width));
      }
    }
  }

  /// Stops co-simulation and releases all resources.
  Future<void> dispose() async {
    _active = false;
    await _clkStableSubscription?.cancel();
    _clkStableSubscription = null;
    _glitchSubscription?.cancel();
    _glitchSubscription = null;
    for (final sub in _inputGlitchSubscriptions) {
      sub.cancel();
    }
    _inputGlitchSubscriptions.clear();
    // Free cached name pointers
    _inputNamePtrs.values.forEach(_free);
    _inputNamePtrs.clear();
    _outputNamePtrs.values.forEach(_free);
    _outputNamePtrs.clear();
    if (_hexBuf != nullptr) {
      _free(_hexBuf);
      _hexBuf = nullptr;
    }
    _inputSignals.clear();
    _outputSignals.clear();
    if (_handle != nullptr) {
      _destroy(_handle);
      _handle = nullptr;
    }
    _lib = null;
  }

  // ══════════════════════════════════════════════════════════════════════
  // C++ Code Generation
  // ══════════════════════════════════════════════════════════════════════

  /// Generates the C++ wrapper with extern "C" API around the ROHD-generated
  /// SystemC module code.
  String _generateWrapper(String generatedSystemC, String topModule) {
    final sb = StringBuffer()
      ..writeln('// Auto-generated SystemC FFI Cosim Wrapper')
      ..writeln('// Module: $topModule')
      ..writeln()
      ..writeln('#include <systemc.h>')
      ..writeln('#include <cstring>')
      ..writeln('#include <string>')
      ..writeln('#include <iostream>')
      ..writeln('using namespace std;')
      ..writeln()
      ..writeln('// ═══ ROHD-Generated SystemC Module(s) ═══')
      ..writeln()
      ..writeln(generatedSystemC)
      ..writeln()
      ..writeln('// ═══ FFI Cosim Context ═══')
      ..writeln()
      ..writeln('struct CosimContext {');

    // All input signal declarations (including clocks as sc_signal<bool>)
    for (final entry in _inputWidths.entries) {
      final type = SystemCSynthesisResult.systemCType(entry.value);
      sb.writeln('    sc_signal<$type> ${entry.key};');
    }
    // Output signal declarations
    for (final entry in _outputWidths.entries) {
      final type = SystemCSynthesisResult.systemCType(entry.value);
      sb.writeln('    sc_signal<$type> ${entry.key};');
    }

    sb
      ..writeln('    $topModule* dut;')
      ..writeln('};')
      ..writeln()
      ..writeln('extern "C" {')
      ..writeln()
      ..writeln('// Required by SystemC linker — we never call it directly')
      ..writeln('int sc_main(int, char*[]) { return 0; }')
      ..writeln()
      ..writeln('// Track whether the kernel has been initialized')
      ..writeln('static CosimContext* _active_ctx = nullptr;')
      ..writeln()
      // ──── sc_cosim_create ────
      ..writeln('void* sc_cosim_create(const char* name) {')
      ..writeln('    // If a context already exists (same process, new test),')
      ..writeln('    // just return the existing one after resetting signals.')
      ..writeln('    if (_active_ctx != nullptr) {')
      ..writeln('        // Reset all input signals to 0');

    for (final entry in _inputWidths.entries) {
      final type = SystemCSynthesisResult.systemCType(entry.value);
      sb.writeln('        _active_ctx->${entry.key}.write($type(0));');
    }

    sb
      ..writeln('        return static_cast<void*>(_active_ctx);')
      ..writeln('    }')
      ..writeln()
      ..writeln('    // Guard: cannot create sc_signal after kernel starts')
      ..writeln('    if (sc_get_status() != SC_ELABORATION'
          ' && sc_get_status() != SC_BEFORE_END_OF_ELABORATION) {')
      ..writeln('        return nullptr;  // E113 prevention')
      ..writeln('    }')
      ..writeln()
      ..writeln('    auto* ctx = new CosimContext();')

      // Instantiate DUT
      ..writeln('    ctx->dut = new $topModule("dut");');

    // Bind all inputs (including clocks — driven via sc_signal<bool>)
    for (final name in _inputWidths.keys) {
      sb.writeln('    ctx->dut->$name(ctx->$name);');
    }
    // Bind outputs
    for (final name in _outputWidths.keys) {
      sb.writeln('    ctx->dut->$name(ctx->$name);');
    }

    sb
      ..writeln()
      ..writeln('    // Store context — do NOT call sc_start here.')
      ..writeln('    // Deferring sc_start to the first advance allows')
      ..writeln('    // multiple module types to be elaborated before')
      ..writeln('    // the kernel starts (avoids E113).')
      ..writeln('    _active_ctx = ctx;')
      ..writeln('    return static_cast<void*>(ctx);')
      ..writeln('}')
      ..writeln()
      // ──── sc_cosim_set_input ────
      ..writeln('void sc_cosim_set_input(void* handle, const char* name,'
          ' uint64_t value) {')
      ..writeln('    auto* ctx = static_cast<CosimContext*>(handle);');

    _generateInputDispatch(sb, narrow: true);

    sb
      ..writeln('}')
      ..writeln()
      // ──── sc_cosim_set_input_wide ────
      ..writeln('void sc_cosim_set_input_wide(void* handle, const char* name,'
          ' const char* hex_value) {')
      ..writeln('    auto* ctx = static_cast<CosimContext*>(handle);');

    _generateInputDispatch(sb, narrow: false);

    sb
      ..writeln('}')
      ..writeln()
      // ──── sc_cosim_get_output ────
      ..writeln(
          'uint64_t sc_cosim_get_output(void* handle, const char* name) {')
      ..writeln('    auto* ctx = static_cast<CosimContext*>(handle);');

    _generateOutputDispatch(sb, narrow: true);

    sb
      ..writeln('    return 0;')
      ..writeln('}')
      ..writeln()
      // ──── sc_cosim_get_output_wide ────
      ..writeln('const char* sc_cosim_get_output_wide(void* handle,'
          ' const char* name) {')
      ..writeln('    auto* ctx = static_cast<CosimContext*>(handle);')
      ..writeln('    static char _buf[512];');

    _generateOutputDispatch(sb, narrow: false);

    sb
      ..writeln("    _buf[0] = '0'; _buf[1] = 0;")
      ..writeln('    return _buf;')
      ..writeln('}')
      ..writeln()
      // ──── sc_cosim_advance ────
      ..writeln('void sc_cosim_advance(void* handle, uint64_t time_ps) {')
      ..writeln('    // End elaboration on first advance (allows multiple')
      ..writeln('    // module types to be instantiated before starting).')
      ..writeln('    if (sc_get_status() == SC_ELABORATION) {')
      ..writeln('        sc_start(SC_ZERO_TIME);')
      ..writeln('    }')
      ..writeln('    if (time_ps == 0) {')
      ..writeln('        // Zero-time advance: process delta cycles only.')
      ..writeln('        // Use SC_ZERO_TIME explicitly (some implementations')
      ..writeln('        // treat sc_time(0,SC_PS) differently).')
      ..writeln('        sc_start(SC_ZERO_TIME);')
      ..writeln('    } else {')
      ..writeln(
          '        sc_start(sc_time(static_cast<double>(time_ps), SC_PS));')
      ..writeln('    }')
      ..writeln('}')
      ..writeln()
      // ──── sc_cosim_destroy ────
      ..writeln('void sc_cosim_destroy(void* handle) {')
      ..writeln('    // Do NOT delete or sc_stop — the SystemC kernel is a')
      ..writeln('    // process-wide singleton. The context is reused if')
      ..writeln('    // sc_cosim_create is called again (same module).')
      ..writeln('    // This avoids E113 "insert primitive channel failed".')
      ..writeln('}')
      ..writeln()
      ..writeln('} // extern "C"');

    return sb.toString();
  }

  /// Generates the if-else chain for setting input signals.
  void _generateInputDispatch(StringBuffer sb, {required bool narrow}) {
    var first = true;
    for (final entry in _inputWidths.entries) {
      final name = entry.key;
      final width = entry.value;

      if (narrow && width > 64) {
        continue;
      }
      if (!narrow && width <= 64) {
        continue;
      }

      final ifStr = first ? '    if' : '    } else if';
      first = false;

      sb.writeln('$ifStr (strcmp(name, "$name") == 0) {');
      if (narrow) {
        final type = SystemCSynthesisResult.systemCType(width);
        sb.writeln('        ctx->$name.write(static_cast<$type>(value));');
      } else {
        sb
          ..writeln('        sc_biguint<$width> v(hex_value);')
          ..writeln('        ctx->$name.write(v);');
      }
    }
    if (!first) {
      sb.writeln('    }');
    }
  }

  /// Generates the if-else chain for reading output signals.
  void _generateOutputDispatch(StringBuffer sb, {required bool narrow}) {
    var first = true;
    for (final entry in _outputWidths.entries) {
      final name = entry.key;
      final width = entry.value;

      if (narrow && width > 64) {
        continue;
      }
      if (!narrow && width <= 64) {
        continue;
      }

      final ifStr = first ? '    if' : '    } else if';
      first = false;

      sb.writeln('$ifStr (strcmp(name, "$name") == 0) {');
      if (narrow) {
        sb.writeln('        return static_cast<uint64_t>(ctx->$name.read());');
      } else {
        sb
          ..writeln('        sc_biguint<$width> v = ctx->$name.read();')
          ..writeln('        string s = v.to_string(SC_HEX_US);')
          ..writeln('        strncpy(_buf, s.c_str(), sizeof(_buf)-1);')
          ..writeln('        _buf[sizeof(_buf)-1] = 0;')
          ..writeln('        return _buf;');
      }
    }
    if (!first) {
      sb.writeln('    }');
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // String/Memory Utilities (no package:ffi dependency)
  // ══════════════════════════════════════════════════════════════════════

  /// Allocates a null-terminated C string from a Dart string.
  static Pointer<Void> _toCString(String s) {
    final bytes = utf8.encode(s);
    final ptr = _malloc(bytes.length + 1);
    final charPtr = ptr.cast<Uint8>();
    for (var i = 0; i < bytes.length; i++) {
      (charPtr + i).value = bytes[i];
    }
    (charPtr + bytes.length).value = 0;
    return ptr;
  }

  /// Reads a null-terminated C string into a Dart string.
  static String _fromCString(Pointer<Char> ptr) {
    final bytes = <int>[];
    var i = 0;
    while (true) {
      final byte = (ptr.cast<Uint8>() + i).value;
      if (byte == 0) {
        break;
      }
      bytes.add(byte);
      i++;
    }
    return utf8.decode(bytes);
  }

  // ══════════════════════════════════════════════════════════════════════
  // SystemC Path Resolution (mirrors SimCompare)
  // ══════════════════════════════════════════════════════════════════════

  static const _defaultHome = '/opt/systemc/include';
  static const _defaultLib = '/opt/systemc/lib';

  static String? _resolveHome(String scHome) {
    if (scHome.isNotEmpty && Directory(scHome).existsSync()) {
      return scHome;
    }
    if (Directory(_defaultHome).existsSync()) {
      return _defaultHome;
    }
    return null;
  }

  static String? _resolveLib(String scLib) {
    if (scLib.isNotEmpty && Directory(scLib).existsSync()) {
      return scLib;
    }
    if (Directory(_defaultLib).existsSync()) {
      return _defaultLib;
    }
    return null;
  }

  static String _detectCxxStd(String scLib) {
    try {
      final r = Process.runSync('nm', ['-D', '$scLib/libsystemc.so']);
      if (r.exitCode == 0) {
        final out = r.stdout as String;
        if (out.contains('cxx202002L')) {
          return 'c++20';
        }
        if (out.contains('cxx201703L')) {
          return 'c++17';
        }
      }
    } on Object {
      // ignore
    }
    return 'c++20';
  }
}

/// Cached state for a loaded SystemC cosim shared library.
class _LoadedCosimLib {
  final DynamicLibrary lib;
  final Pointer<Void> handle;
  final _SetInputDart setInput;
  final _SetInputWideDart setInputWide;
  final _GetOutputDart getOutput;
  final _GetOutputWideDart getOutputWide;
  final _AdvanceDart advance;
  final _DestroyDart destroy;

  _LoadedCosimLib({
    required this.lib,
    required this.handle,
    required this.setInput,
    required this.setInputWide,
    required this.getOutput,
    required this.getOutputWide,
    required this.advance,
    required this.destroy,
  });
}
