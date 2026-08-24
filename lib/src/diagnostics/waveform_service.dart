// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_service.dart
// Base waveform service: file output with filtering, timescale, and
// flush/overwrite control.  Designed to be subclassed by the DevTools
// streaming variant.
//
// 2026 June
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/config.dart';
import 'package:rohd/src/utilities/sanitizer.dart';
import 'package:rohd/src/utilities/timestamper.dart';
import 'package:rohd/src/utilities/uniquifier.dart';

// ─── Supporting types ────────────────────────────────────────────────────────

/// The output format for waveform capture.
enum WaveOutputFormat {
  /// Value Change Dump — the classic text-based waveform format.
  vcd,

  /// Fast Signal Trace — a compact binary format.
  ///
  /// Requires an FST writer to be available; see the DevTools subclass for
  /// a fully FST-backed implementation.
  fst;

  /// The filename extension associated with this format.
  String get fileExtension => switch (this) {
        WaveOutputFormat.vcd => 'vcd',
        WaveOutputFormat.fst => 'fst',
      };

  /// The media type associated with this format.
  String get mediaType => switch (this) {
        WaveOutputFormat.vcd => 'text/x-vcd',
        WaveOutputFormat.fst => 'application/vnd.gtkwave.fst',
      };
}

/// Policy applied when the output file already exists at construction time.
enum OverwritePolicy {
  /// Silently overwrite any existing file.
  overwrite,

  /// Throw a [FileSystemException] if the file already exists.
  failIfExists,
}

// ─── Service ─────────────────────────────────────────────────────────────────

/// A waveform capture service that records signal changes.
///
/// This is the base class for waveform capture.  It handles:
/// - Signal collection (with optional [signalFilter])
/// - In-memory VCD output with configurable [timescale]
/// - Selective recording via [startTime] / [stopTime]
/// - Optional file output with periodic buffer flushing and [overwritePolicy]
/// - Optional registration with [ModuleServices]
///
/// **Subclassing for DevTools streaming:**
///
/// Override the protected hooks below to intercept the simulation event loop
/// without re-implementing the file-writing logic:
///
/// - [onSignalCollected] — called once per tracked signal at startup; use
///   it to register signals in a VM-service index.
/// - [onValueChange] — called for every value-change event within the
///   [startTime]/[stopTime] window; use it to feed an in-memory store for
///   streaming.
/// - [onTimestampCapture] — called once per simulation timestamp that
///   contains at least one change; the full changed-signal set is passed.
/// - [onSimulationEnd] — called after the final timestamp is written and
///   the file is closed; use it to finalise any streaming buffers.
///
/// Example subclass skeleton:
/// ```dart
/// class DevToolsWaveformService extends WaveformService {
///   DevToolsWaveformService(
///     super.module, {
///     super.outputDirectory,
///     super.outputBaseName,
///   });
///
///   @override
///   void onSignalCollected(Logic signal) {
///     super.onSignalCollected(signal);
///     _registerWithVmService(signal);
///   }
///
///   @override
///   void onValueChange(Logic signal, int timestamp) {
///     super.onValueChange(signal, timestamp);
///     _recordInMemory(signal, timestamp);
///   }
/// }
/// ```
class WaveformService extends ArtifactProducingService {
  /// The most recently registered [WaveformService], or `null`.
  static WaveformService? current;

  /// Path of the output waveform file.
  ///
  /// Derived from [outputDirectory], [outputBaseName], and [format].
  String get outputFilePath => '$outputDirectory${Platform.pathSeparator}'
      '${outputFileName ?? '$outputBaseName.${format.fileExtension}'}';

  /// Exact output filename override.
  ///
  /// Prefer [outputBaseName] for new service code. This override exists for
  /// compatibility with legacy APIs that accepted an arbitrary output path.
  final String? outputFileName;

  /// Output format.
  final WaveOutputFormat format;

  /// Optional predicate that determines whether a given [Logic] signal is
  /// captured.
  ///
  /// When `null`, all non-[Const] signals in the hierarchy are captured,
  /// matching the legacy waveform dumper behaviour.
  final bool Function(Logic signal)? signalFilter;

  /// VCD timescale string, e.g. `'1ps'`, `'1ns'`.
  final String timescale;

  /// Simulation time at which recording begins.
  ///
  /// Signals are still collected before this time so they appear in the scope
  /// definition, but value-change events are suppressed until [startTime] is
  /// reached.  `null` means "from the very start".
  final int? startTime;

  /// Simulation time at which recording ends.
  ///
  /// Value-change events after this time are suppressed.  `null` means "until
  /// end of simulation".
  final int? stopTime;

  /// Number of characters accumulated in the write buffer before it is flushed
  /// to disk.
  final int flushBufferSize;

  /// What to do when the output file already exists.
  final OverwritePolicy overwritePolicy;

  /// Whether to register this service with [ModuleServices] for inspection.
  final bool register;

  /// Whether waveform bytes are written to [outputFilePath].
  ///
  /// When `false`, the service retains its waveform bytes in memory and exposes
  /// them through [artifacts].
  final bool writeToFile;

  // ─── Internal file-writing state ─────────────────────────────

  /// Sink writing to [outputFilePath] when [writeToFile] is true.
  IOSink? _outFileSink;

  /// Write buffer; flushed when it exceeds [flushBufferSize].
  final StringBuffer _fileBuffer = StringBuffer();

  /// The complete waveform output retained for streaming artifacts.
  final StringBuffer _inMemoryOutput = StringBuffer();

  /// Counter for assigning compact signal markers in the VCD.
  int _signalMarkerIdx = 0;

  /// Maps each captured [Logic] to its VCD marker string.
  final Map<Logic, String> _signalToMarkerMap = {};

  /// Signals that changed during the current simulation timestamp.
  final Set<Logic> _changedThisTimestamp = HashSet<Logic>();

  /// The timestamp currently being accumulated.
  int _currentDumpingTimestamp = Simulator.time;

  // ─── Constructor ─────────────────────────────────────────────

  /// Creates a [WaveformService] for [module].
  ///
  /// [module] must be built before construction.
  ///
  /// [outputDirectory] defaults to the current directory and [outputBaseName]
  /// defaults to [Module.definitionName]. The selected [format] determines the
  /// output filename extension. Only [WaveOutputFormat.vcd] is currently
  /// supported by this service.
  ///
  /// Use the optional constructor parameters to configure format, filtering,
  /// timescale, start/stop times, flush size, and overwrite policy.
  WaveformService(
    Module module, {
    super.outputDirectory,
    super.outputBaseName,
    this.outputFileName,
    this.format = WaveOutputFormat.vcd,
    this.signalFilter,
    this.timescale = '1ps',
    this.startTime,
    this.stopTime,
    this.flushBufferSize = 100000,
    this.overwritePolicy = OverwritePolicy.overwrite,
    this.register = true,
    this.writeToFile = false,
  }) : super(module) {
    if (!module.hasBuilt) {
      throw Exception(
        'Module must be built before creating WaveformService. '
        'Call build() first.',
      );
    }
    if (format != WaveOutputFormat.vcd) {
      throw UnsupportedError(
        'Waveform format ${format.name} is not supported by WaveformService.',
      );
    }

    if (writeToFile && overwritePolicy == OverwritePolicy.failIfExists) {
      final f = File(outputFilePath);
      if (f.existsSync()) {
        throw FileSystemException(
          'Waveform output file already exists and overwritePolicy is '
          'failIfExists.',
          outputFilePath,
        );
      }
    }

    if (writeToFile) {
      _outFileSink =
          (File(outputFilePath)..createSync(recursive: true)).openWrite();
    }

    _collectSignals();
    _writeHeader();
    _writeScope();

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

  // ─── Extensibility hooks ──────────────────────────────────────

  /// Called once for each [Logic] signal that passes
  /// [signalFilter] during initial signal collection.
  ///
  /// Override in a subclass to register signals with an in-memory store,
  /// VM service index, or FST handle map.  Always call `super` first.
  @protected
  void onSignalCollected(Logic signal) {}

  /// Called for every value-change event on [signal] at [timestamp].
  ///
  /// Only called within the [startTime] / [stopTime] window.
  ///
  /// Override in a subclass to feed an in-memory waveform store or
  /// streaming buffer.  Always call `super` first.
  @protected
  void onValueChange(Logic signal, int timestamp) {}

  /// Called once per simulation timestamp that contains at least one change,
  /// after all value-change events for that timestamp have been processed.
  ///
  /// [changed] is the set of signals that changed at [timestamp].
  ///
  /// Override in a subclass to flush incremental streaming payloads.
  /// Always call `super` first.
  @protected
  void onTimestampCapture(int timestamp, Set<Logic> changed) {}

  /// Called after the final timestamp has been written and the file is closed.
  ///
  /// Override in a subclass to finalise any streaming buffers or emit
  /// end-of-simulation notifications.
  @protected
  void onSimulationEnd() {}

  // ─── Internal signal collection ──────────────────────────────

  void _collectSignals() {
    final modulesToParse = <Module>[module];
    for (var i = 0; i < modulesToParse.length; i++) {
      final m = modulesToParse[i];
      for (final sig in m.signals) {
        if (sig is Const) {
          continue;
        }
        if (signalFilter != null && !signalFilter!(sig)) {
          continue;
        }

        _signalToMarkerMap[sig] = 's${_signalMarkerIdx++}';
        onSignalCollected(sig);

        sig.changed.listen((_) {
          _changedThisTimestamp.add(sig);
        });
      }

      for (final subm in m.subModules) {
        if (subm is InlineSystemVerilog) {
          continue;
        }
        modulesToParse.add(subm);
      }
    }
  }

  // ─── VCD output helpers ───────────────────────────────────────

  void _writeHeader() {
    final header = '''
\$date
  ${Timestamper.stamp()}
\$end
\$version
  ROHD v${Config.version}
\$end
\$comment
  Generated by ROHD - www.github.com/intel/rohd
\$end
\$timescale $timescale \$end
''';
    _writeToBuffer(header);
  }

  void _writeScope() {
    var scopeString = _computeScopeString(module);
    scopeString += '\$enddefinitions \$end\n';
    scopeString += '\$dumpvars\n';
    _writeToBuffer(scopeString);
    _signalToMarkerMap.keys.forEach(_writeSignalValueUpdate);
    _writeToBuffer('\$end\n');
  }

  String _computeScopeString(Module m, {int indent = 0}) {
    final moduleSignalUniquifier = Uniquifier();
    final padding = List.filled(indent, '  ').join();
    var scopeString = '$padding\$scope module ${m.uniqueInstanceName} \$end\n';
    final innerScopeString = StringBuffer();

    for (final sig in m.signals) {
      if (!_signalToMarkerMap.containsKey(sig)) {
        continue;
      }
      final width = sig.width;
      final marker = _signalToMarkerMap[sig];
      var signalName = Sanitizer.sanitizeSV(sig.name);
      signalName = moduleSignalUniquifier.getUniqueName(
        initialName: signalName,
        reserved: sig.isPort,
      );
      innerScopeString.write(
        '  $padding\$var wire $width $marker $signalName \$end\n',
      );
    }
    for (final subModule in m.subModules) {
      innerScopeString.write(
        _computeScopeString(subModule, indent: indent + 1),
      );
    }
    if (innerScopeString.isEmpty) {
      return '';
    }

    scopeString += innerScopeString.toString();
    scopeString += '$padding\$upscope \$end\n';
    return scopeString;
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

    _writeToBuffer('#$timestamp\n');

    final snapshot = Set<Logic>.of(_changedThisTimestamp);
    for (final sig in snapshot) {
      _writeSignalValueUpdate(sig);
      onValueChange(sig, timestamp);
    }
    _changedThisTimestamp.clear();

    onTimestampCapture(timestamp, snapshot);
  }

  void _writeSignalValueUpdate(Logic signal) {
    final binaryValue = signal.value.reversed
        .toList()
        .map((e) => e.toString(includeWidth: false))
        .join();
    final updateValue = signal.width > 1
        ? 'b$binaryValue '
        : signal.value.toString(includeWidth: false);
    final marker = _signalToMarkerMap[signal];
    _writeToBuffer('$updateValue$marker\n');
  }

  // ─── Buffered I/O ─────────────────────────────────────────────

  void _writeToBuffer(String contents) {
    _fileBuffer.write(contents);
    _inMemoryOutput.write(contents);
    if (_fileBuffer.length > flushBufferSize) {
      _flushBuffer();
    }
  }

  void _flushBuffer() {
    _outFileSink?.write(_fileBuffer.toString());
    _fileBuffer.clear();
  }

  Future<void> _terminate() async {
    _flushBuffer();
    await _outFileSink?.flush();
    await _outFileSink?.close();
  }

  // ─── Inspection ───────────────────────────────────────────────

  /// The waveform artifact produced by this service.
  @override
  Iterable<ModuleServiceArtifact> get artifacts => [
        ModuleServiceArtifact(
          fileName: outputFileName ?? '$outputBaseName.${format.fileExtension}',
          mediaType: format.mediaType,
          openRead: () => Stream.value(utf8.encode(_inMemoryOutput.toString())),
        ),
      ];

  /// Returns a JSON-serialisable summary of this service.
  @override
  Map<String, Object> toJson() => {
        'outputDirectory': outputDirectory,
        'outputBaseName': outputBaseName,
        'outputFilePath': outputFilePath,
        'writeToFile': writeToFile,
        'format': format.name,
        'signalCount': _signalToMarkerMap.length,
        'timescale': timescale,
        if (startTime != null) 'startTime': startTime!,
        if (stopTime != null) 'stopTime': stopTime!,
      };
}
