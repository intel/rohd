// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// wave_dumper.dart
// Waveform dumper for a given module hierarchy, dumps to ".vcd" or ".fst" file.
//
// 2021 May 7
// Author: Max Korbel <max.korbel@intel.com>
// 2026 February - Added FST format support
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:collection';
import 'dart:io';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/config.dart';
import 'package:rohd/src/utilities/sanitizer.dart';
import 'package:rohd/src/utilities/timestamper.dart';
import 'package:rohd/src/utilities/uniquifier.dart';

/// Waveform output format.
enum WaveFormat {
  /// VCD (Value Change Dump) — IEEE 1364 standard text format.
  vcd,

  /// FST (Fast Signal Trace) — GTKWave binary format.
  ///
  /// FST files are compressed, support random access, and are compatible
  /// with GTKWave, Surfer, and the wellen reader.
  fst,
}

/// A waveform dumper for simulations.
///
/// Outputs to VCD or FST format at [outputPath]. [module] must be built prior
/// to attaching the [WaveDumper].
///
/// The waves will only dump to the file periodically and then once the
/// simulation has completed.
///
///
/// To output FST (compressed binary) instead of VCD (text):
/// ```dart
/// WaveDumper(module, outputPath: 'waves.fst', format: WaveFormat.fst);
/// ```
class WaveDumper {
  /// The [Module] being dumped.
  final Module module;

  /// The output filepath of the generated waveforms.
  final String outputPath;

  /// The waveform output format (VCD or FST).
  final WaveFormat format;

  /// The FST writer configuration (only used when [format] is
  /// [WaveFormat.fst]).
  final FstWriterConfig? fstConfig;

  /// The file to write dumped output waveform to (VCD only).
  File? _outputFile;

  /// A sink to write contents into [_outputFile] (VCD only).
  IOSink? _outFileSink;

  /// A buffer for contents before writing to the file sink (VCD only).
  final StringBuffer _fileBuffer = StringBuffer();

  /// A counter for tracking signal names in the VCD file.
  int _signalMarkerIdx = 0;

  /// Stores the mapping from [Logic] to signal marker in the VCD file.
  final Map<Logic, String> _signalToMarkerMap = {};

  /// Stores the mapping from [Logic] to FST signal handle (FST only).
  final Map<Logic, FstSignalHandle> _signalToFstHandle = {};

  /// The FST writer instance (FST only).
  FstWriter? _fstWriter;

  /// A set of all [Logic]s that have changed in this timestamp so far.
  ///
  /// This spans across multiple inject or changed events if they are in the
  /// same timestamp of the [Simulator].
  final Set<Logic> _changedLogicsThisTimestamp = HashSet<Logic>();

  /// The timestamp which is currently being collected for a dump.
  ///
  /// When the [Simulator] time progresses beyond this, it will dump all the
  /// signals that have changed up until that point at this saved time value.
  int _currentDumpingTimestamp = Simulator.time;

  /// Attaches a [WaveDumper] to record all signal changes in a simulation of
  /// [module] in a waveform file at [outputPath].
  ///
  /// The output [format] defaults to [WaveFormat.vcd] for VCD text files.
  /// Set to [WaveFormat.fst] for compressed FST binary files.
  ///
  WaveDumper(
    this.module, {
    this.outputPath = 'waves.vcd',
    this.format = WaveFormat.vcd,
    this.fstConfig,
  }) {
    if (!module.hasBuilt) {
      throw Exception(
          'Module must be built before passed to dumper.  Call build() first.');
    }

    if (format == WaveFormat.fst) {
      _initFst();
    } else {
      _initVcd();
    }

    Simulator.preTick.listen((args) {
      if (Simulator.time != _currentDumpingTimestamp) {
        if (_changedLogicsThisTimestamp.isNotEmpty) {
          // no need to write blank timestamps
          _captureTimestamp(_currentDumpingTimestamp);
        }
        _currentDumpingTimestamp = Simulator.time;
      }
    });

    Simulator.registerEndOfSimulationAction(() async {
      _captureTimestamp(Simulator.time);

      await _terminate();
    });
  }

  /// Number of characters in the buffer after which it will
  /// write contents to the output file.
  static const _fileBufferLimit = 100000;

  // ─────────────── VCD initialization ───────────────

  /// Initializes VCD output.
  void _initVcd() {
    _outputFile = File(outputPath)..createSync(recursive: true);
    _outFileSink = _outputFile!.openWrite();
    _collectAllSignals();
    _writeVcdHeader();
    _writeVcdScope();
  }

  // ─────────────── FST initialization ───────────────

  /// Initializes FST output.
  void _initFst() {
    _fstWriter =
        FstWriter(outputPath, config: fstConfig ?? const FstWriterConfig());

    // Walk module hierarchy and declare signals
    _collectAllSignalsFst(module);

    // Write header after all signals declared
    _fstWriter!.writeHeader();
  }

  /// Collects signals from the module hierarchy and declares them in the FST
  /// writer.
  void _collectAllSignalsFst(Module m) {
    _fstWriter!.pushScope(m.uniqueInstanceName);
    var hasSignals = false;

    final moduleSignalUniquifier = Uniquifier();

    for (final sig in m.signals) {
      if (sig is Const) {
        continue;
      }

      hasSignals = true;
      final baseName = Sanitizer.sanitizeSV(sig.name);
      final signalName = moduleSignalUniquifier.getUniqueName(
          initialName: baseName, reserved: sig.isPort);

      final handle = _fstWriter!.declareSignal(
        signalName,
        sig.width,
        direction: sig.isPort
            ? (sig.isInput ? FstVarDirection.input : FstVarDirection.output)
            : FstVarDirection.implicit,
      );
      _signalToFstHandle[sig] = handle;

      sig.changed.listen((args) {
        _changedLogicsThisTimestamp.add(sig);
      });
    }

    for (final subm in m.subModules) {
      if (subm is InlineSystemVerilog) {
        continue;
      }
      _collectAllSignalsFst(subm);
    }

    // Only pop scope if we had content (matching VCD empty-scope behavior)
    if (!hasSignals &&
        m.subModules.where((s) => s is! InlineSystemVerilog).isEmpty) {
      // empty scope — we still need to pop what we pushed
    }
    _fstWriter!.popScope();
  }

  // ─────────────── Shared methods ───────────────

  /// Buffers [contents] to be written to the VCD output file.
  void _writeToBuffer(String contents) {
    _fileBuffer.write(contents);

    if (_fileBuffer.length > _fileBufferLimit) {
      _writeToFile();
    }
  }

  /// Writes all pending items in the [_fileBuffer] to the VCD file.
  void _writeToFile() {
    _outFileSink?.write(_fileBuffer.toString());
    _fileBuffer.clear();
  }

  /// Terminates the waveform dumping, including closing the file.
  Future<void> _terminate() async {
    if (format == WaveFormat.fst) {
      // For FST: flush any remaining changes and finalize
      _fstWriter?.finish();
    } else {
      // For VCD: flush buffer and close file
      _writeToFile();
      await _outFileSink?.flush();
      await _outFileSink?.close();
    }
  }

  /// Registers all signal value changes to write updates to the dumped VCD.
  void _collectAllSignals() {
    final modulesToParse = <Module>[module];
    for (var i = 0; i < modulesToParse.length; i++) {
      final m = modulesToParse[i];
      for (final sig in m.signals) {
        if (sig is Const) {
          // constant values are "boring" to inspect
          continue;
        }

        _signalToMarkerMap[sig] = 's${_signalMarkerIdx++}';
        sig.changed.listen((args) {
          _changedLogicsThisTimestamp.add(sig);
        });
      }

      for (final subm in m.subModules) {
        if (subm is InlineSystemVerilog) {
          // the InlineSystemVerilog modules are "boring" to inspect
          continue;
        }
        modulesToParse.add(subm);
      }
    }
  }

  // ─────────────── VCD-specific methods ───────────────

  /// Writes the top header for the VCD file.
  void _writeVcdHeader() {
    final dateString = Timestamper.stamp();
    const timescale = '1ps';
    final header = '''
\$date
  $dateString
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

  /// Writes the scope of the VCD, including signal and hierarchy declarations,
  /// as well as initial values.
  void _writeVcdScope() {
    var scopeString = _computeScopeString(module);
    scopeString += '\$enddefinitions \$end\n';
    scopeString += '\$dumpvars\n';
    _writeToBuffer(scopeString);
    _signalToMarkerMap.keys.forEach(_writeSignalValueUpdate);

    _writeToBuffer('\$end\n');
  }

  /// Generates the top of the scope string (signal and hierarchy definitions).
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
      final baseName = Sanitizer.sanitizeSV(sig.name);
      final signalName = moduleSignalUniquifier.getUniqueName(
          initialName: baseName, reserved: sig.isPort);
      innerScopeString
          .write('  $padding\$var wire $width $marker $signalName \$end\n');
    }

    for (final subModule in m.subModules) {
      innerScopeString
          .write(_computeScopeString(subModule, indent: indent + 1));
    }
    if (innerScopeString.isEmpty) {
      // no need to dump empty scopes
      return '';
    }
    scopeString += innerScopeString.toString();
    scopeString += '$padding\$upscope \$end\n';
    return scopeString;
  }

  // ─────────────── Timestamp capture ───────────────

  /// Captures all signal changes at the current timestamp.
  void _captureTimestamp(int timestamp) {
    if (format == WaveFormat.fst) {
      _captureTimestampFst(timestamp);
    } else {
      _captureTimestampVcd(timestamp);
    }
  }

  /// Captures a VCD timestamp: writes the timestamp marker and changed values.
  void _captureTimestampVcd(int timestamp) {
    final timestampString = '#$timestamp\n';
    _writeToBuffer(timestampString);

    _changedLogicsThisTimestamp
      ..forEach(_writeSignalValueUpdate)
      ..clear();
  }

  /// Captures an FST timestamp: emits value changes for all changed signals.
  void _captureTimestampFst(int timestamp) {
    for (final sig in _changedLogicsThisTimestamp) {
      final handle = _signalToFstHandle[sig];
      if (handle == null) {
        continue;
      }

      final binaryValue = sig.value.reversed
          .toList()
          .map((e) => e.toString(includeWidth: false))
          .join();
      _fstWriter!.emitValueChange(timestamp, handle, binaryValue);
    }
    _changedLogicsThisTimestamp.clear();
  }

  /// Writes the current value of [signal] to the VCD.
  void _writeSignalValueUpdate(Logic signal) {
    final binaryValue = signal.value.reversed
        .toList()
        .map((e) => e.toString(includeWidth: false))
        .join();
    final updateValue = signal.width > 1
        ? 'b$binaryValue '
        : signal.value.toString(includeWidth: false);
    final marker = _signalToMarkerMap[signal];
    final updateString = '$updateValue$marker\n';
    _writeToBuffer(updateString);
  }
}

/// Deprecated: use [WaveDumper] instead.
@Deprecated('Use WaveDumper instead')
typedef Dumper = WaveDumper;
