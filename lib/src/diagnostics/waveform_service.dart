// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_service.dart
// Base waveform service: capture module signal changes to waveform writers.
//
// 2026 June
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:collection';

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/sanitizer.dart';
import 'package:rohd/src/utilities/uniquifier.dart';

/// A waveform capture service that writes signal changes to a file.
class WaveformService implements ModuleService {
  /// The most recently registered [WaveformService], or `null`.
  static WaveformService? current;

  /// The top-level [Module] being captured.
  @override
  final Module module;

  /// Path of the output waveform file.
  final String outputPath;

  /// Output format.
  final WaveOutputFormat format;

  /// Optional predicate that determines whether a given [Logic] signal is
  /// captured.
  final bool Function(Logic signal)? signalFilter;

  /// VCD timescale string, e.g. `'1ps'`, `'1ns'`.
  final String timescale;

  /// Simulation time at which recording begins.
  final int? startTime;

  /// Simulation time at which recording ends.
  final int? stopTime;

  /// Number of characters accumulated in the VCD write buffer before it is
  /// flushed to disk.
  final int flushBufferSize;

  /// What to do when the output file already exists.
  final OverwritePolicy overwritePolicy;

  /// Whether to register this service with [ModuleServices] for inspection.
  final bool register;

  /// Whether to enable DevTools streaming.
  ///
  /// The base [WaveformService] stores this flag but takes no action on it.
  /// Downstream DevTools integrations can subclass or observe the hooks below.
  final bool enableDevToolsStreaming;

  /// The FST writer configuration (only used when [format] is
  /// [WaveOutputFormat.fst]).
  final FstWriterConfig? fstConfig;

  late final WaveformWriter _writer;

  /// Maps each captured [Logic] to its writer-specific signal handle.
  final Map<Logic, Object> _signalHandles = <Logic, Object>{};

  /// Signals that changed during the current simulation timestamp.
  final Set<Logic> _changedThisTimestamp = HashSet<Logic>();

  /// The timestamp currently being accumulated.
  int _currentDumpingTimestamp = Simulator.time;

  /// Creates a [WaveformService] for [module].
  ///
  /// [module] must be built before construction.
  WaveformService(
    this.module, {
    this.outputPath = 'waves.vcd',
    this.format = WaveOutputFormat.vcd,
    this.signalFilter,
    this.timescale = '1ps',
    this.startTime,
    this.stopTime,
    this.flushBufferSize = 100000,
    this.overwritePolicy = OverwritePolicy.overwrite,
    this.register = true,
    this.enableDevToolsStreaming = false,
    this.fstConfig,
  }) {
    if (!module.hasBuilt) {
      throw Exception(
        'Module must be built before creating WaveformService. '
        'Call build() first.',
      );
    }

    _writer = _createWriter();
    _collectSignals(module);
    _writer.finishDeclarations(
      _signalHandles.entries.map(
        (entry) => WaveformInitialValue(entry.value, _binaryValue(entry.key)),
      ),
      timestamp: Simulator.time,
    );

    Simulator.preTick.listen((_) {
      if (Simulator.time != _currentDumpingTimestamp) {
        if (_changedThisTimestamp.isNotEmpty) {
          _captureTimestamp(_currentDumpingTimestamp);
        }
        _currentDumpingTimestamp = Simulator.time;
      }
    });

    Simulator.registerEndOfSimulationAction(() async {
      _captureTimestamp(Simulator.time);
      await _terminate();
      onSimulationEnd();
    });

    if (register) {
      current = this;
      ModuleServices.instance.register<WaveformService>(this);
    }
  }

  /// The concrete output writer used by this service.
  @protected
  WaveformWriter get writer => _writer;

  /// Called once for each [Logic] signal that passes [signalFilter].
  @protected
  void onSignalCollected(Logic signal) {}

  /// Called for every value-change event on [signal] at [timestamp].
  @protected
  void onValueChange(Logic signal, int timestamp) {}

  /// Called once per simulation timestamp that contains at least one change.
  @protected
  void onTimestampCapture(int timestamp, Set<Logic> changed) {}

  /// Called after the final timestamp has been written and the file is closed.
  @protected
  void onSimulationEnd() {}

  WaveformWriter _createWriter() {
    switch (format) {
      case WaveOutputFormat.vcd:
        return VcdWaveformWriter(
          outputPath,
          timescale: timescale,
          flushBufferSize: flushBufferSize,
          overwritePolicy: overwritePolicy,
        );
      case WaveOutputFormat.fst:
        return FstWaveformWriter(
          outputPath,
          config: fstConfig ?? const FstWriterConfig(),
        );
    }
  }

  bool _collectSignals(Module module) {
    final moduleSignalUniquifier = Uniquifier();
    var hasContents = false;

    _writer.pushScope(module.uniqueInstanceName);

    for (final sig in module.signals) {
      if (sig is Const) {
        continue;
      }
      if (signalFilter != null && !signalFilter!(sig)) {
        continue;
      }

      hasContents = true;
      final baseName = Sanitizer.sanitizeSV(sig.name);
      final signalName = moduleSignalUniquifier.getUniqueName(
        initialName: baseName,
        reserved: sig.isPort,
      );
      final handle = _writer.declareSignal(
        signalName,
        sig.width,
        direction: _directionOf(sig),
      );
      _signalHandles[sig] = handle;
      onSignalCollected(sig);

      sig.changed.listen((_) {
        _changedThisTimestamp.add(sig);
      });
    }

    for (final subModule in module.subModules) {
      if (subModule is InlineSystemVerilog) {
        continue;
      }
      hasContents = _collectSignals(subModule) || hasContents;
    }

    _writer.popScope();
    return hasContents;
  }

  WaveformSignalDirection _directionOf(Logic signal) {
    if (!signal.isPort) {
      return WaveformSignalDirection.implicit;
    }
    return signal.isInput
        ? WaveformSignalDirection.input
        : WaveformSignalDirection.output;
  }

  bool _isInRecordingWindow(int timestamp) {
    if (startTime != null && timestamp < startTime!) {
      return false;
    }
    if (stopTime != null && timestamp > stopTime!) {
      return false;
    }
    return true;
  }

  void _captureTimestamp(int timestamp) {
    if (!_isInRecordingWindow(timestamp)) {
      _changedThisTimestamp.clear();
      return;
    }

    final snapshot = Set<Logic>.of(_changedThisTimestamp);
    final changes = <WaveformValueChange>[
      for (final sig in snapshot)
        WaveformValueChange(_signalHandles[sig]!, _binaryValue(sig)),
    ];

    if (changes.isNotEmpty) {
      _writer.emitValueChanges(timestamp, changes);
    }

    for (final sig in snapshot) {
      onValueChange(sig, timestamp);
    }
    _changedThisTimestamp.clear();

    if (snapshot.isNotEmpty) {
      onTimestampCapture(timestamp, snapshot);
    }
  }

  String _binaryValue(Logic signal) => signal.value.reversed
      .toList()
      .map((e) => e.toString(includeWidth: false))
      .join();

  Future<void> _terminate() => _writer.close();

  /// Returns a JSON-serialisable summary of this service.
  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'outputPath': outputPath,
        'format': format.name,
        'signalCount': _signalHandles.length,
        'timescale': timescale,
        if (startTime != null) 'startTime': startTime,
        if (stopTime != null) 'stopTime': stopTime,
        'writer': _writer.toJson(),
      };
}
