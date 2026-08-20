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
  fst,
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

/// Common backend contract for waveform file formats.
abstract class WaveformWriter {
  /// The file format emitted by this writer.
  WaveOutputFormat get format;

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
}

/// VCD implementation of [WaveformWriter].
class VcdWaveformWriter implements WaveformWriter {
  /// Creates a VCD writer at [outputPath].
  VcdWaveformWriter(
    this.outputPath, {
    this.timescale = '1ps',
    this.flushBufferSize = 100000,
    this.overwritePolicy = OverwritePolicy.overwrite,
  }) {
    if (overwritePolicy == OverwritePolicy.failIfExists) {
      final existingFile = File(outputPath);
      if (existingFile.existsSync()) {
        throw FileSystemException(
          'Waveform output file already exists and overwritePolicy is '
          'failIfExists.',
          outputPath,
        );
      }
    }

    _outputFile = File(outputPath)..createSync(recursive: true);
    _outFileSink = _outputFile.openWrite();
    _writeHeader();
  }

  /// The output file path.
  final String outputPath;

  /// VCD timescale string, e.g. `'1ps'`, `'1ns'`.
  final String timescale;

  /// Number of characters accumulated before flushing to disk.
  final int flushBufferSize;

  /// Existing-file policy.
  final OverwritePolicy overwritePolicy;

  late final File _outputFile;
  late final IOSink _outFileSink;
  final StringBuffer _fileBuffer = StringBuffer();
  final StringBuffer _scopeBuffer = StringBuffer();
  final Map<Object, int> _handleWidths = <Object, int>{};
  var _signalMarkerIdx = 0;
  var _indent = 0;
  var _closed = false;

  @override
  WaveOutputFormat get format => WaveOutputFormat.vcd;

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
  void emitValueChanges(
    int timestamp,
    Iterable<WaveformValueChange> changes,
  ) {
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
    await _outFileSink.flush();
    await _outFileSink.close();
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'format': format.name,
        'signalCount': _handleWidths.length,
        'timescale': timescale,
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
\$timescale $timescale \$end
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
    _fileBuffer.write(contents);
    if (_fileBuffer.length > flushBufferSize) {
      _flushBuffer();
    }
  }

  void _flushBuffer() {
    _outFileSink.write(_fileBuffer.toString());
    _fileBuffer.clear();
  }
}

/// FST implementation of [WaveformWriter].
class FstWaveformWriter implements WaveformWriter {
  /// Creates an FST writer at [outputPath].
  FstWaveformWriter(
    String outputPath, {
    FstWriterConfig config = const FstWriterConfig(),
  }) : writer = FstWriter(outputPath, config: config);

  /// The low-level FST binary writer.
  final FstWriter writer;

  @override
  WaveOutputFormat get format => WaveOutputFormat.fst;

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
      writer.declareSignal(
        name,
        width,
        direction: _fstDirection(direction),
      );

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
  void emitValueChanges(
    int timestamp,
    Iterable<WaveformValueChange> changes,
  ) {
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
