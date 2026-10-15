// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_writer.dart
// Common output backend API for waveform capture services.
//
// 2026 July 17
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/config.dart';
import 'package:rohd/src/utilities/timestamper.dart';

/// The output format for waveform capture.
enum WaveOutputFormat {
  /// Value Change Dump, the classic text-based waveform format.
  vcd,

  /// Fast Signal Trace, a compact binary format.
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

  /// Whether waveform data can be queried from the output file.
  bool get supportsOnDiskQueries => switch (this) {
        WaveOutputFormat.vcd => false,
        WaveOutputFormat.fst => true,
      };
}

/// The physical duration represented by one unit of [Simulator.time].
///
/// This only controls the time metadata emitted to waveform files. It does
/// not rescale timestamp numbers or change simulator scheduling. The supported
/// values are the VCD-standard 1, 10, and 100 multiples from femtoseconds
/// through seconds.
enum WaveformTimeScale {
  /// 100 seconds per simulation-time unit.
  hundredSeconds(2, '100s'),

  /// 10 seconds per simulation-time unit.
  tenSeconds(1, '10s'),

  /// 1 second per simulation-time unit.
  oneSecond(0, '1s'),

  /// 100 milliseconds per simulation-time unit.
  hundredMilliseconds(-1, '100ms'),

  /// 10 milliseconds per simulation-time unit.
  tenMilliseconds(-2, '10ms'),

  /// 1 millisecond per simulation-time unit.
  oneMillisecond(-3, '1ms'),

  /// 100 microseconds per simulation-time unit.
  hundredMicroseconds(-4, '100us'),

  /// 10 microseconds per simulation-time unit.
  tenMicroseconds(-5, '10us'),

  /// 1 microsecond per simulation-time unit.
  oneMicrosecond(-6, '1us'),

  /// 100 nanoseconds per simulation-time unit.
  hundredNanoseconds(-7, '100ns'),

  /// 10 nanoseconds per simulation-time unit.
  tenNanoseconds(-8, '10ns'),

  /// 1 nanosecond per simulation-time unit.
  oneNanosecond(-9, '1ns'),

  /// 100 picoseconds per simulation-time unit.
  hundredPicoseconds(-10, '100ps'),

  /// 10 picoseconds per simulation-time unit.
  tenPicoseconds(-11, '10ps'),

  /// 1 picosecond per simulation-time unit.
  onePicosecond(-12, '1ps'),

  /// 100 femtoseconds per simulation-time unit.
  hundredFemtoseconds(-13, '100fs'),

  /// 10 femtoseconds per simulation-time unit.
  tenFemtoseconds(-14, '10fs'),

  /// 1 femtosecond per simulation-time unit.
  oneFemtosecond(-15, '1fs');

  /// Creates a waveform timescale with its base-10 seconds [exponent] and
  /// VCD representation.
  const WaveformTimeScale(this.exponent, this.vcdValue);

  /// The base-10 exponent in seconds used by the FST encoding.
  final int exponent;

  /// The corresponding VCD timescale value.
  final String vcdValue;

  /// Returns the supported timescale with the given base-10 seconds
  /// [exponent].
  ///
  /// Throws an [ArgumentError] when [exponent] cannot be represented by both
  /// waveform formats.
  static WaveformTimeScale fromExponent(int exponent) {
    for (final timeScale in values) {
      if (timeScale.exponent == exponent) {
        return timeScale;
      }
    }
    throw ArgumentError.value(
      exponent,
      'exponent',
      'must be between -15 and 2 inclusive',
    );
  }
}

/// Policy applied when the output file already exists at construction time.
enum OverwritePolicy {
  /// Silently overwrite any existing file.
  overwrite,

  /// Throw a [FileSystemException] if the file already exists.
  failIfExists,
}

/// Direction metadata for a signal emitted into a waveform file.
enum WaveformSignalDirection {
  /// Input port.
  input,

  /// Output port.
  output,

  /// Internal or implicit signal.
  implicit,
}

/// Initial value for a declared waveform signal.
class WaveformInitialValue {
  /// The writer-specific handle returned by [WaveformWriter.declareSignal].
  final Object handle;

  /// The MSB-first binary value string.
  final String value;

  /// Creates an initial value entry.
  const WaveformInitialValue(this.handle, this.value);
}

/// Timestamped value change for a declared waveform signal.
class WaveformValueChange extends WaveformInitialValue {
  /// Creates a value-change entry.
  const WaveformValueChange(super.handle, super.value);
}

/// A signal available from a format-independent waveform query.
class WaveformQuerySignal {
  /// Creates a query signal.
  const WaveformQuerySignal({
    required this.index,
    required this.name,
    required this.width,
  });

  /// The zero-based index of this signal within its waveform.
  final int index;

  /// The signal's declared name.
  final String name;

  /// The signal's declared width.
  final int width;
}

/// A timestamped value returned by a waveform query.
class WaveformQueryValueChange {
  /// Creates a queried value change.
  const WaveformQueryValueChange(this.time, this.value);

  /// Simulation timestamp of this change.
  final int time;

  /// The MSB-first binary value string.
  final String value;
}

/// Format-independent capability for querying waveform values.
abstract interface class WaveformQuery {
  /// The signals available for querying.
  List<WaveformQuerySignal> get signals;

  /// Returns emitted values for [signal] within the inclusive time range.
  List<WaveformQueryValueChange> changes(
    WaveformQuerySignal signal, {
    required int startTime,
    required int endTime,
  });

  /// Returns [signal]'s value at or immediately before [time].
  String? valueAt(WaveformQuerySignal signal, int time);
}

/// Common backend contract for waveform file formats.
abstract class WaveformWriter {
  /// The file format emitted by this writer.
  WaveOutputFormat get format;

  /// Whether this writer can query waveform values from its output.
  bool get supportsQueries;

  /// Creates a format-independent query capability, when supported.
  WaveformQuery? createWaveformQuery();

  /// Pushes a scope onto the declaration hierarchy.
  void pushScope(String name);

  /// Pops the current declaration scope.
  void popScope();

  /// Declares a signal and returns a writer-specific handle.
  Object declareSignal(
    String name,
    int width, {
    required WaveformSignalDirection direction,
  });

  /// Finishes declarations and emits initial values.
  void finishDeclarations(
    Iterable<WaveformInitialValue> initialValues, {
    required int timestamp,
  });

  /// Emits all value changes for [timestamp].
  void emitValueChanges(int timestamp, Iterable<WaveformValueChange> changes);

  /// Flushes and closes the waveform output.
  Future<void> close();

  /// Returns a JSON-serialisable summary of writer state.
  Map<String, Object?> toJson();

  /// Returns the retained waveform text, when supported and enabled.
  String? get inMemoryOutput;
}

/// VCD implementation of [WaveformWriter].
class VcdWaveformWriter implements WaveformWriter {
  /// Creates a VCD writer at [outputPath].
  VcdWaveformWriter(
    this.outputPath, {
    this.timescale = WaveformTimeScale.onePicosecond,
    this.flushBufferSize = 100000,
    this.memoryBuffer,
    this.writeToFile = true,
  }) {
    if (writeToFile) {
      _outFileSink =
          (File(outputPath)..createSync(recursive: true)).openWrite();
    }
    _writeHeader();
  }

  /// The output file path.
  final String outputPath;

  /// The physical duration represented by one simulation-time unit.
  final WaveformTimeScale timescale;

  /// Number of characters accumulated before flushing to disk.
  final int flushBufferSize;

  /// Optional buffer receiving a complete copy of the VCD output.
  final StringBuffer? memoryBuffer;

  /// Whether VCD bytes are written to [outputPath].
  final bool writeToFile;

  IOSink? _outFileSink;
  final StringBuffer _fileBuffer = StringBuffer();
  final StringBuffer _scopeBuffer = StringBuffer();
  final Map<Object, int> _handleWidths = <Object, int>{};
  var _signalMarkerIdx = 0;
  var _indent = 0;
  var _closed = false;

  @override
  WaveOutputFormat get format => WaveOutputFormat.vcd;

  @override
  bool get supportsQueries => false;

  @override
  WaveformQuery? createWaveformQuery() => null;

  @override
  String? get inMemoryOutput => memoryBuffer?.toString();

  @override
  void pushScope(String name) {
    final padding = List.filled(_indent, '  ').join();
    _scopeBuffer.write('$padding\$scope module $name \$end\n');
    _indent++;
  }

  @override
  void popScope() {
    _indent--;
    final padding = List.filled(_indent, '  ').join();
    _scopeBuffer.write('$padding\$upscope \$end\n');
  }

  @override
  Object declareSignal(
    String name,
    int width, {
    required WaveformSignalDirection direction,
  }) {
    final marker = 's${_signalMarkerIdx++}';
    final padding = List.filled(_indent, '  ').join();
    _scopeBuffer.write('$padding\$var wire $width $marker $name \$end\n');
    _handleWidths[marker] = width;
    return marker;
  }

  @override
  void finishDeclarations(
    Iterable<WaveformInitialValue> initialValues, {
    required int timestamp,
  }) {
    _writeToBuffer(_scopeBuffer.toString());
    _writeToBuffer('\$enddefinitions \$end\n');
    _writeToBuffer('\$dumpvars\n');
    for (final initialValue in initialValues) {
      _writeValueUpdate(initialValue.handle, initialValue.value);
    }
    _writeToBuffer('\$end\n');
  }

  @override
  void emitValueChanges(int timestamp, Iterable<WaveformValueChange> changes) {
    _writeToBuffer('#$timestamp\n');
    for (final change in changes) {
      _writeValueUpdate(change.handle, change.value);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _flushBuffer();
    await _outFileSink?.flush();
    await _outFileSink?.close();
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'format': format.name,
        'signalCount': _handleWidths.length,
        'timescale': timescale.vcdValue,
      };

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
\$timescale ${timescale.vcdValue} \$end
''';
    _writeToBuffer(header);
  }

  void _writeValueUpdate(Object handle, String value) {
    final width = _handleWidths[handle];
    if (width == null) {
      throw StateError('Unknown VCD signal handle: $handle');
    }
    final updateValue = width > 1 ? 'b$value ' : value;
    _writeToBuffer('$updateValue$handle\n');
  }

  void _writeToBuffer(String contents) {
    memoryBuffer?.write(contents);
    if (writeToFile) {
      _fileBuffer.write(contents);
    }
    if (writeToFile && _fileBuffer.length > flushBufferSize) {
      _flushBuffer();
    }
  }

  void _flushBuffer() {
    if (writeToFile) {
      _outFileSink!.write(_fileBuffer.toString());
      _fileBuffer.clear();
    }
  }
}

/// FST implementation of [WaveformWriter].
class FstWaveformWriter implements WaveformWriter {
  /// Creates an FST writer at [outputPath].
  FstWaveformWriter(
    String outputPath, {
    required this.timescale,
    FstWriterConfig config = const FstWriterConfig(),
  }) : writer = FstWriter(
          outputPath,
          config: config,
          timescaleExponent: timescale.exponent,
        );

  /// The physical duration represented by one simulation-time unit.
  final WaveformTimeScale timescale;

  /// The low-level FST binary writer.
  final FstWriter writer;

  /// Creates a bounded-memory query provider for this writer's waveform.
  FstWaveformQuery createQuery() => FstWaveformQuery(writer);

  @override
  WaveOutputFormat get format => WaveOutputFormat.fst;

  @override
  bool get supportsQueries => true;

  @override
  WaveformQuery createWaveformQuery() =>
      _FstWaveformQueryAdapter(createQuery());

  @override
  String? get inMemoryOutput => null;

  @override
  void pushScope(String name) {
    writer.pushScope(name);
  }

  @override
  void popScope() {
    writer.popScope();
  }

  @override
  Object declareSignal(
    String name,
    int width, {
    required WaveformSignalDirection direction,
  }) =>
      writer.declareSignal(name, width, direction: _fstDirection(direction));

  @override
  void finishDeclarations(
    Iterable<WaveformInitialValue> initialValues, {
    required int timestamp,
  }) {
    writer.writeHeader();
    for (final initialValue in initialValues) {
      writer.emitValueChange(
        timestamp,
        initialValue.handle as FstSignalHandle,
        initialValue.value,
      );
    }
  }

  @override
  void emitValueChanges(int timestamp, Iterable<WaveformValueChange> changes) {
    for (final change in changes) {
      writer.emitValueChange(
        timestamp,
        change.handle as FstSignalHandle,
        change.value,
      );
    }
  }

  @override
  Future<void> close() async {
    writer.finish();
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'format': format.name,
        'timescale': timescale.vcdValue,
        'maxChangesPerBlock': writer.config.maxChangesPerBlock,
      };

  FstVarDirection _fstDirection(WaveformSignalDirection direction) {
    switch (direction) {
      case WaveformSignalDirection.input:
        return FstVarDirection.input;
      case WaveformSignalDirection.output:
        return FstVarDirection.output;
      case WaveformSignalDirection.implicit:
        return FstVarDirection.implicit;
    }
  }
}

class _FstWaveformQueryAdapter implements WaveformQuery {
  _FstWaveformQueryAdapter(this._query)
      : signals = List.unmodifiable([
          for (var index = 0;
              index < _query.writer.signalInfoList.length;
              index++)
            WaveformQuerySignal(
              index: index,
              name: _query.writer.signalInfoList[index].name,
              width: _query.writer.signalInfoList[index].width,
            ),
        ]);

  final FstWaveformQuery _query;

  @override
  final List<WaveformQuerySignal> signals;

  FstSignalHandle _handle(WaveformQuerySignal signal) {
    if (signal.index < 0 || signal.index >= signals.length) {
      throw RangeError.index(signal.index, signals, 'signal');
    }
    return FstSignalHandle(signal.index + 1);
  }

  @override
  List<WaveformQueryValueChange> changes(
    WaveformQuerySignal signal, {
    required int startTime,
    required int endTime,
  }) =>
      _query
          .changes(
            _handle(signal),
            startTime: startTime,
            endTime: endTime,
          )
          .map(
            (change) => WaveformQueryValueChange(change.time, change.value),
          )
          .toList(growable: false);

  @override
  String? valueAt(WaveformQuerySignal signal, int time) =>
      _query.valueAt(_handle(signal), time);
}
