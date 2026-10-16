// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// debug_session.dart
// Explicit lifecycle for the bundled DevTools debugging surfaces.
//
// 2026 October
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';

/// An opt-in debugging workflow for one built module hierarchy.
///
/// Start a session before constructing hardware so [SourceTracer] can capture
/// construction sites. After building the hierarchy, call [attach] to register
/// netlist and trace services and begin live waveform capture. Call [close]
/// when the debugging session is no longer needed.
///
/// ```dart
/// final debug = DebugSession.start();
/// final dut = MyModule(...);
/// await dut.build();
/// debug.attach(dut);
///
/// // Inspect NetlistService.current, TraceService.current, and live waves.
///
/// debug.close();
/// ```
class DebugSession {
  DebugSession._(
    this._sourceTracer, {
    this.packageRoot,
    this.netlistConfiguration = const NetlistSynthesizerConfiguration(),
  });

  /// Starts an explicit debugging session.
  ///
  /// Source capture begins immediately, so call this before constructing any
  /// [Logic] or [Module] objects whose provenance should be available.
  ///
  /// A session requires exclusive ownership of source and live waveform
  /// capture. Stop an existing session before starting another one.
  factory DebugSession.start({
    String? packageRoot,
    NetlistSynthesizerConfiguration netlistConfiguration =
        const NetlistSynthesizerConfiguration(),
  }) {
    if (SourceTracer.isActive) {
      throw StateError(
        'A SourceTracer is already active; close that debugging session '
        'before starting another one.',
      );
    }
    final waveforms = WaveformDataService.instance;
    if (waveforms.isInitialized || waveforms.isRecording) {
      throw StateError(
        'Live waveform capture is already initialized; stop that debugging '
        'session before starting another one.',
      );
    }
    return DebugSession._(
      SourceTracer.activate(),
      packageRoot: packageRoot,
      netlistConfiguration: netlistConfiguration,
    );
  }

  final SourceTracer _sourceTracer;

  /// Package root used to make source paths relative in registered services.
  final String? packageRoot;

  /// Configuration used to synthesize the registered netlist.
  final NetlistSynthesizerConfiguration netlistConfiguration;

  NetlistService? _netlist;
  TraceService? _trace;
  NetlistService? _previousNetlist;
  TraceService? _previousTrace;
  bool _ownsWaveformRecording = false;
  bool _closed = false;

  /// Whether [attach] has registered the debugging services.
  bool get isAttached => _netlist != null;

  /// Whether [close] has released this session's resources.
  bool get isClosed => _closed;

  /// The registered netlist service.
  ///
  /// Throws a [StateError] until [attach] completes.
  NetlistService get netlist =>
      _netlist ??
      (throw StateError('Call attach(module) before accessing the netlist.'));

  /// The registered source-trace service.
  ///
  /// Throws a [StateError] until [attach] completes.
  TraceService get trace =>
      _trace ??
      (throw StateError('Call attach(module) before accessing the trace.'));

  /// Attaches debugging services to a built [module] hierarchy.
  ///
  /// This registers [NetlistService] and [TraceService] for discovery by
  /// DevTools, then begins live waveform capture through
  /// [WaveformDataService].
  void attach(Module module) {
    if (_closed) {
      throw StateError('Cannot attach a closed DebugSession.');
    }
    if (_netlist != null) {
      throw StateError('DebugSession is already attached.');
    }
    if (!module.hasBuilt) {
      throw ModuleNotBuiltException(module);
    }

    _previousNetlist = NetlistService.current;
    _previousTrace = TraceService.current;

    final netlist = NetlistService(
      module,
      configuration: netlistConfiguration,
      packageRoot: packageRoot,
    );
    final trace = TraceService(module, packageRoot: packageRoot);
    WaveformDataService.init(module);
    _ownsWaveformRecording = WaveformDataService.instance.startRecording();
    _netlist = netlist;
    _trace = trace;
  }

  /// Releases services and capture started by this session.
  ///
  /// Existing netlist and trace registrations are restored when this session
  /// was the current owner. Source tracing is deactivated only if this session
  /// still owns the active tracer.
  void close() {
    if (_closed) {
      return;
    }

    if (_ownsWaveformRecording) {
      WaveformDataService.instance
        ..stopRecording()
        ..clear();
      _ownsWaveformRecording = false;
    }

    final netlist = _netlist;
    if (identical(NetlistService.current, netlist)) {
      final previous = _previousNetlist;
      if (previous == null) {
        ModuleServices.instance.unregister<NetlistService>();
      } else {
        ModuleServices.instance.register<NetlistService>(previous);
      }
    }

    final trace = _trace;
    if (identical(TraceService.current, trace)) {
      final previous = _previousTrace;
      if (previous == null) {
        ModuleServices.instance.unregister<TraceService>();
      } else {
        ModuleServices.instance.register<TraceService>(previous);
      }
    }

    SourceTracer.clearIfCurrent(_sourceTracer);
    _closed = true;
  }
}
