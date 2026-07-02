// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// fst_writer.dart
// Pure Dart implementation of FST (Fast Signal Trace) binary writer.
//
// Writes valid FST files compatible with GTKWave, Surfer, wellen reader.
// Reference: fst-reader 0.14.2 (io.rs, types.rs) and fstapi.c from GTKWave.
//
// 2026 February
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:rohd/rohd.dart';

/// Configuration for the FST writer.
class FstWriterConfig {
  /// Timescale exponent. The timescale is 10^exponent seconds.
  /// Default: -12 (picoseconds).
  final int timescaleExponent;

  /// Zlib compression level (0-9). Higher = smaller but slower.
  /// Default: 4.
  final int compressionLevel;

  /// Writer version string embedded in the file header.
  final String version;

  /// File type: Verilog, VHDL, or combined.
  final FstFileType fileType;

  /// Maximum number of value changes to buffer before auto-flushing
  /// a VcData block to disk. Set to 0 (default) to disable auto-flush
  /// and write a single block at [FstWriter.finish].
  ///
  /// When non-zero, [FstWriter.emitValueChange] automatically calls
  /// [FstWriter.flushBlock] once the buffer reaches this threshold.
  /// This bounds memory usage and makes historical data available on
  /// disk for read-back.
  final int maxChangesPerBlock;

  /// Creates configuration for the FST writer.
  const FstWriterConfig({
    this.timescaleExponent = -12,
    this.compressionLevel = 4,
    this.version = 'ROHD FST Writer',
    this.fileType = FstFileType.verilog,
    this.maxChangesPerBlock = 0,
  });
}

/// A handle to a declared signal in the FST file.
///
/// Handles are 1-based (matching VST convention). Index 0 is unused.
class FstSignalHandle {
  /// The 1-based handle value.
  final int handle;

  /// Creates a signal handle from a 1-based handle value.
  const FstSignalHandle(this.handle);
}

/// Metadata about a flushed VcData block in the FST file.
///
/// Each entry in [FstWriter.blockIndex] represents a block that has been
/// written to disk and can be read back independently for on-demand
/// signal queries without loading the entire file into memory.
class FstBlockIndex {
  /// File offset of the block_type byte in the FST file.
  final int fileOffset;

  /// Section length (the section_length field from the block header). The full
  /// block occupies bytes [fileOffset .. fileOffset + 1 + sectionLength).
  final int sectionLength;

  /// First timestamp in this block.
  final int startTime;

  /// Last timestamp in this block.
  final int endTime;

  /// Creates a block index entry.
  const FstBlockIndex({
    required this.fileOffset,
    required this.sectionLength,
    required this.startTime,
    required this.endTime,
  });
}

/// Public metadata about a declared signal in the FST writer.
class FstSignalInfo {
  /// Signal name.
  final String name;

  /// Bit width (number of bits for digital signals, 8 for real).
  final int width;

  /// Whether this is a real-valued (f64) signal.
  final bool isReal;

  /// Creates signal info.
  const FstSignalInfo({
    required this.name,
    required this.width,
    required this.isReal,
  });
}

/// Internal: information about a declared signal.
class _SignalDecl {
  final String name;
  final int width;
  final FstVarType varType;
  final FstVarDirection direction;
  final bool isReal;

  _SignalDecl({
    required this.name,
    required this.width,
    required this.varType,
    required this.direction,
    this.isReal = false,
  });

  /// The geometry file_format value for this signal.
  int get geometryValue {
    if (isReal) {
      return 0;
    }
    return width; // 1 for 1-bit, N for N-bit
  }

  /// The number of bytes this signal occupies in the frame section.
  int get frameLength {
    if (isReal) {
      return 8;
    }
    return width; // 1 byte per bit for character-encoded values
  }
}

/// Internal: a buffered value change.
class _ValueChange {
  final int time;
  final int handleIndex; // 0-based
  final String value;

  _ValueChange(this.time, this.handleIndex, this.value);
}

/// Internal: an entry in the hierarchy being built.
sealed class _HierarchyEntry {}

class _ScopeEntry extends _HierarchyEntry {
  final FstScopeType type;
  final String name;
  final String component;
  _ScopeEntry(this.type, this.name, {this.component = ''});
}

class _UpScopeEntry extends _HierarchyEntry {}

class _VarEntry extends _HierarchyEntry {
  final FstVarType varType;
  final FstVarDirection direction;
  final String name;
  final int width;
  final int handle; // 1-based
  _VarEntry(this.varType, this.direction, this.name, this.width, this.handle);
}

/// Pure Dart writer for the FST (Fast Signal Trace) binary format.
///
/// Usage:
/// ```dart
/// final writer = FstWriter('output.fst');
/// writer.pushScope('top');
/// final clk = writer.declareSignal('clk', 1);
/// final data = writer.declareSignal('data', 8);
/// writer.popScope();
/// writer.writeHeader();
///
/// writer.emitValueChange(0, clk, '0');
/// writer.emitValueChange(0, data, '00000000');
/// writer.emitValueChange(5, clk, '1');
/// writer.emitValueChange(10, clk, '0');
///
/// writer.finish();
/// ```
class FstWriter {
  /// The output file path.
  final String filePath;

  /// Writer configuration.
  final FstWriterConfig config;

  /// All declared signals (0-indexed).
  final List<_SignalDecl> _signals = [];

  /// Hierarchy entries in declaration order.
  final List<_HierarchyEntry> _hierEntries = [];

  /// Scope counts for header.
  int _scopeCount = 0;

  /// Variable counts for header (including aliases).
  int _varCount = 0;

  /// Buffered value changes.
  final List<_ValueChange> _changes = [];

  /// The start time of the simulation.
  int _startTime = 0;

  /// The end time of the simulation.
  int _endTime = 0;

  /// Whether the header has been written yet.
  bool _headerWritten = false;

  /// The output file random access handle.
  late final RandomAccessFile _file;

  /// Current value of each signal (tracks latest emitted value).
  /// Initialized in [writeHeader].
  late List<String> _currentValues;

  /// Base values for the next block's frame section.
  /// Updated after each [flushBlock] call.
  late List<String> _nextFrameBase;

  /// Index of flushed VcData blocks for read-back.
  final List<FstBlockIndex> _blockIndex = [];

  /// Number of VcData blocks written so far.
  int _vcSectionCount = 0;

  /// Creates an FST writer that will write to [filePath].
  FstWriter(this.filePath, {this.config = const FstWriterConfig()}) {
    final file = File(filePath)..createSync(recursive: true);
    _file = file.openSync(mode: FileMode.write);
  }

  /// Pushes a new scope onto the hierarchy.
  void pushScope(
    String name, {
    FstScopeType type = FstScopeType.module,
    String component = '',
  }) {
    _hierEntries.add(_ScopeEntry(type, name, component: component));
    _scopeCount++;
  }

  /// Pops the current scope.
  void popScope() {
    _hierEntries.add(_UpScopeEntry());
  }

  /// Declares a signal and returns its handle.
  ///
  /// [name] is the signal name. [width] is the bit width (1 for single bit).
  /// Returns an [FstSignalHandle] used for emitting value changes.
  FstSignalHandle declareSignal(
    String name,
    int width, {
    FstVarType varType = FstVarType.wire,
    FstVarDirection direction = FstVarDirection.implicit,
  }) {
    final handle = _signals.length + 1; // 1-based
    final decl = _SignalDecl(
      name: name,
      width: width,
      varType: varType,
      direction: direction,
      isReal: varType == FstVarType.real || varType == FstVarType.realParameter,
    );
    _signals.add(decl);
    _hierEntries.add(_VarEntry(varType, direction, name, width, handle));
    _varCount++;
    return FstSignalHandle(handle);
  }

  /// Writes the FST file header.
  ///
  /// Must be called after all signals are declared and before any value
  /// changes. The header is initially written with placeholder values for
  /// start_time and end_time, which are fixed up during [finish].
  void writeHeader() {
    if (_headerWritten) {
      throw StateError('Header already written');
    }
    _writeHeaderBlock();
    _headerWritten = true;

    // Initialize value tracking for incremental block flushing
    final defaults = List<String>.generate(_signals.length, (i) {
      final sig = _signals[i];
      return sig.isReal ? '0.0' : 'x' * sig.width;
    });
    _currentValues = List<String>.from(defaults);
    _nextFrameBase = List<String>.from(defaults);
  }

  /// Records a value change for a signal at a given simulation time.
  ///
  /// [time] is the simulation timestamp.
  /// [handle] is the signal handle returned by [declareSignal].
  /// [value] is the new value as a string (e.g., '0', '1', '01010101', 'x').
  void emitValueChange(int time, FstSignalHandle handle, String value) {
    if (!_headerWritten) {
      throw StateError('Must call writeHeader() before emitting value changes');
    }
    if (_endTime < time) {
      _endTime = time;
    }
    _changes.add(_ValueChange(time, handle.handle - 1, value));
    _currentValues[handle.handle - 1] = value;

    // Auto-flush if threshold is reached
    if (config.maxChangesPerBlock > 0 &&
        _changes.length >= config.maxChangesPerBlock) {
      flushBlock();
    }
  }

  /// Finalizes the FST file: flushes remaining value changes, writes
  /// geometry and hierarchy blocks, fixes up the header, and closes the file.
  void finish() {
    if (!_headerWritten) {
      writeHeader();
    }

    // Flush any remaining buffered changes as a final VcData block
    flushBlock();

    _writeGeometryBlock();
    _writeHierarchyBlock();
    _fixupHeader();

    _file.closeSync();
  }

  /// Releases resources. Call [finish] first for a valid file.
  void dispose() {
    try {
      _file.closeSync();
    } on FileSystemException {
      // already closed
    }
  }

  /// Flushes buffered value changes to disk as a VcData block.
  ///
  /// After flushing, the changes are cleared from memory and the block
  /// is recorded in [blockIndex] for later read-back. This enables
  /// incremental writing where only recent unflushed changes remain
  /// in memory while historical data lives on disk.
  ///
  /// Does nothing if no changes are buffered.
  void flushBlock() {
    if (_changes.isEmpty) {
      return;
    }
    if (!_headerWritten) {
      throw StateError('Must call writeHeader() before flushing blocks');
    }

    // Sort changes by time, then by handle
    _changes.sort((a, b) {
      final cmp = a.time.compareTo(b.time);
      return cmp != 0 ? cmp : a.handleIndex.compareTo(b.handleIndex);
    });

    final blockStart = _changes.first.time;
    final blockEnd = _changes.last.time;

    // Build frame: carry-over state from previous block, overridden by
    // any changes at this block's start time.
    final frameValues = List<String>.from(_nextFrameBase);
    for (final c in _changes) {
      if (c.time == blockStart) {
        frameValues[c.handleIndex] = c.value;
      }
    }

    final blockOffset = _file.positionSync();
    _writeVcDataBlock(
      blockStartTime: blockStart,
      blockEndTime: blockEnd,
      frameValues: frameValues,
    );
    final blockEndPos = _file.positionSync();

    // Record block in the index for read-back
    _blockIndex.add(
      FstBlockIndex(
        fileOffset: blockOffset,
        sectionLength: blockEndPos - blockOffset - 1,
        startTime: blockStart,
        endTime: blockEnd,
      ),
    );
    _vcSectionCount++;

    // Update global time range
    if (_vcSectionCount == 1) {
      _startTime = blockStart;
    }
    _endTime = blockEnd;

    // Carry-over state for next block's frame
    _nextFrameBase = List<String>.from(_currentValues);
    _changes.clear();
  }

  // ─── Public query API for hybrid disk+memory access ───

  /// Index of all flushed VcData blocks.
  ///
  /// Each entry contains the file offset and time range, enabling
  /// the `FstBlockReader` to read specific blocks on demand.
  List<FstBlockIndex> get blockIndex => List.unmodifiable(_blockIndex);

  /// Number of declared signals.
  int get signalCount => _signals.length;

  /// Public metadata about each declared signal (indexed by handle-1).
  List<FstSignalInfo> get signalInfoList => _signals
      .map((s) => FstSignalInfo(name: s.name, width: s.width, isReal: s.isReal))
      .toList();

  /// The output file handle for read-back by `FstBlockReader`.
  ///
  /// **Warning**: The caller must not close or modify the file position
  /// without restoring it. The writer uses this same handle for writing.
  RandomAccessFile get file => _file;

  /// Query unflushed value changes for a specific signal handle.
  ///
  /// Returns changes from the hot buffer for signal [handleIndex] (0-based)
  /// within the time range \[startTime, endTime\].
  List<({int time, String value})> queryHotBuffer(
    int handleIndex,
    int startTime,
    int endTime,
  ) =>
      _changes
          .where(
            (c) =>
                c.handleIndex == handleIndex &&
                c.time >= startTime &&
                c.time <= endTime,
          )
          .map((c) => (time: c.time, value: c.value))
          .toList();

  /// Returns the current (latest) value of signal [handleIndex] (0-based).
  String getCurrentValue(int handleIndex) => _currentValues[handleIndex];

  /// Returns the latest known values of all signals (read-only).
  List<String> get currentValues => List.unmodifiable(_currentValues);

  // ─────────────── Header Block ───────────────

  static const int _headerLength = 329;
  static const int _headerVersionMaxLen = 128;
  static const int _headerDateMaxLen = 119;

  /// Writes the FST_BL_HDR block.
  void _writeHeaderBlock() {
    _file.writeByteSync(FstBlockType.header.value);
    _writeU64(_headerLength); // section_length (fixed size)
    _writeU64(_startTime); // start_time (placeholder)
    _writeU64(_endTime); // end_time (placeholder)
    _writeF64LE(math.e); // double endian test
    _writeU64(0); // memory_used_by_writer
    _writeU64(_scopeCount); // scope_count
    _writeU64(_varCount); // var_count
    _writeU64(_signals.length); // max_var_id_code
    _writeU64(1); // vc_section_count (we write one block)
    _file.writeByteSync(config.timescaleExponent & 0xFF); // timescale_exponent
    _writeFixedString(config.version, _headerVersionMaxLen);
    _writeFixedString(_dateString(), _headerDateMaxLen);
    _file.writeByteSync(config.fileType.value); // file_type
    _writeU64(0); // time_zero
  }

  /// Fixes up the header with actual start/end times and block count.
  void _fixupHeader() {
    final savedPos = _file.positionSync();
    _file.setPositionSync(1 + 8); // skip block_type + section_length
    _writeU64(_startTime);
    _writeU64(_endTime);
    // Fix vc_section_count with actual number of blocks written
    // Layout: block_type(1) + section_length(8) + start_time(8) +
    //   end_time(8) + endian_test(8) + memory_used(8) + scope_count(8) +
    //   var_count(8) + max_var_id(8) = offset 65
    _file.setPositionSync(
      1 + 8 + 8 + 8 + 8 + 8 + 8 + 8 + 8,
    ); // at vc_section_count
    _writeU64(_vcSectionCount);
    _file.setPositionSync(savedPos);
  }

  // ─────────────── Hierarchy Block ───────────────

  static const int _hierTypeScopeBegin = 254;
  static const int _hierTypeUpScope = 255;

  /// Writes the FST_BL_HIER block (zlib/gzip compressed hierarchy).
  void _writeHierarchyBlock() {
    // Build uncompressed hierarchy bytes
    final buf = BytesBuilder(copy: false);
    var handleCount = 0;

    for (final entry in _hierEntries) {
      switch (entry) {
        case _ScopeEntry():
          buf.addByte(_hierTypeScopeBegin);
          buf.addByte(entry.type.value);
          buf.add(_cString(entry.name));
          buf.add(_cString(entry.component));
        case _UpScopeEntry():
          buf.addByte(_hierTypeUpScope);
        case _VarEntry():
          buf.addByte(entry.varType.value);
          buf.addByte(entry.direction.value);
          buf.add(_cString(entry.name));
          buf.add(encodeVarint(entry.width)); // length
          // alias = 0 means "new handle, not an alias"
          buf.add(encodeVarint(0));
          handleCount++;
      }
    }

    final uncompressed = buf.toBytes();
    assert(
      handleCount == _signals.length,
      'Handle count mismatch: $handleCount vs ${_signals.length}',
    );

    // Write as FST_BL_HIER (type 4) with gzip compression
    _file.writeByteSync(FstBlockType.hierarchy.value);
    final sectionLengthPos = _file.positionSync();
    _writeU64(0); // placeholder section_length
    _writeU64(uncompressed.length); // uncompressed_length

    // Write gzip header + deflate-compressed data
    _writeGzipCompressed(uncompressed);

    // Fix section_length
    final endPos = _file.positionSync();
    final sectionLength = endPos - sectionLengthPos;
    _file.setPositionSync(sectionLengthPos);
    _writeU64(sectionLength);
    _file.setPositionSync(endPos);
  }

  // ─────────────── Geometry Block ───────────────

  /// Writes the FST_BL_GEOM block.
  void _writeGeometryBlock() {
    // Build uncompressed geometry: one varint per signal
    final buf = BytesBuilder(copy: false);
    for (final sig in _signals) {
      buf.add(encodeVarint(sig.geometryValue));
    }
    final uncompressed = buf.toBytes();
    final compressed = _zlibCompress(
      uncompressed,
      config.compressionLevel,
      allowRaw: true,
    );

    _file.writeByteSync(FstBlockType.geometry.value);
    final sectionLength = 3 * 8 + compressed.length;
    _writeU64(sectionLength); // section_length
    _writeU64(uncompressed.length); // uncompressed_length
    _writeU64(_signals.length); // max_handle
    _file.writeFromSync(compressed);
  }

  // ─────────────── VcData Block (DynamicAlias2) ───────────────

  /// Writes a single FST_BL_VCDATA_DYN_ALIAS2 block from the current
  /// `_changes` buffer.
  ///
  /// [blockStartTime] and [blockEndTime] are the time range for this block.
  /// [frameValues] contains the initial value of each signal at the block's
  /// start time (carry-over state plus changes at blockStartTime).
  ///
  /// Assumes `_changes` is already sorted by time, then by handle.
  void _writeVcDataBlock({
    required int blockStartTime,
    required int blockEndTime,
    required List<String> frameValues,
  }) {
    // Build sorted unique time table.
    // Only include timestamps that have signal chain entries (i.e., after
    // blockStartTime). Changes at blockStartTime go into the frame section.
    // The fst-reader only reads the frame when time_table[0] > start_time;
    // if blockStartTime were included, the frame would be skipped and all
    // signals would appear as 'x'.
    final timeSet = <int>{};
    for (final c in _changes) {
      if (c.time != blockStartTime) {
        timeSet.add(c.time);
      }
    }
    final timeTable = timeSet.toList()..sort();
    // Map timestamp → index
    final timeToIndex = <int, int>{};
    for (var i = 0; i < timeTable.length; i++) {
      timeToIndex[timeTable[i]] = i;
    }

    // Build per-signal value change chains
    final signalData = _buildSignalData(timeToIndex, blockStartTime);

    // Pack each signal's data (store uncompressed with varint(0) prefix)
    final packedSignals = <Uint8List>[];
    for (final data in signalData) {
      if (data.isEmpty) {
        packedSignals.add(Uint8List(0));
      } else {
        final packed = BytesBuilder(copy: false)
          ..add(encodeVarint(0)) // means "uncompressed"
          ..add(data);
        packedSignals.add(packed.toBytes());
      }
    }

    // Build frame bytes
    final frameBytes = _buildFrameBytes(frameValues);
    final frameCompressed = _zlibCompress(
      frameBytes,
      config.compressionLevel,
      allowRaw: true,
    );

    // Build the signal offset chain (DynamicAlias2 format)
    final chainBytes = _buildOffsetChain(packedSignals);

    // Build time table bytes
    final timeTableBytes = _buildTimeTableBytes(timeTable);

    // Compute memory required for traversal
    var memRequired = 0;
    for (final ps in packedSignals) {
      memRequired += ps.length;
    }

    // Now assemble the VcData block
    _file.writeByteSync(FstBlockType.vcDataDynamicAlias2.value);
    final sectionLengthPos = _file.positionSync();
    _writeU64(0); // placeholder section_length
    _writeU64(blockStartTime); // start_time
    _writeU64(blockEndTime); // end_time
    _writeU64(memRequired); // mem_required_for_traversal

    // Frame section
    _file
      ..writeFromSync(encodeVarint(frameBytes.length)) // unc len
      ..writeFromSync(encodeVarint(frameCompressed.length)) // comp len
      ..writeFromSync(encodeVarint(_signals.length)) // max_handle
      ..writeFromSync(frameCompressed)
      // Value change section
      ..writeFromSync(encodeVarint(_signals.length)) // max_handle
      ..writeByteSync(0x5A); // pack_type = 'Z' (zlib)

    // Write per-signal packed data
    packedSignals.forEach(_file.writeFromSync);

    // Write offset chain
    _file.writeFromSync(chainBytes);
    _writeU64(chainBytes.length); // chain_compressed_length

    // Write time table
    _file.writeFromSync(timeTableBytes);

    // Fix section_length
    final endPos = _file.positionSync();
    final sectionLength = endPos - sectionLengthPos;
    _file.setPositionSync(sectionLengthPos);
    _writeU64(sectionLength);
    _file.setPositionSync(endPos);
  }

  /// Builds frame bytes: the initial value of each signal concatenated.
  Uint8List _buildFrameBytes(List<String> initialValues) {
    final buf = BytesBuilder(copy: false);
    for (var i = 0; i < _signals.length; i++) {
      final sig = _signals[i];
      if (sig.isReal) {
        // Encode as f64 little-endian bytes
        final d = double.tryParse(initialValues[i]) ?? 0.0;
        final bd = ByteData(8)..setFloat64(0, d, Endian.little);
        buf.add(bd.buffer.asUint8List());
      } else {
        // Character-encoded value: one byte per bit
        final val = initialValues[i];
        for (var j = 0; j < sig.width; j++) {
          buf.addByte(j < val.length ? val.codeUnitAt(j) : 0x78); // 'x'
        }
      }
    }
    return buf.toBytes();
  }

  /// Builds per-signal value change encoded data.
  ///
  /// Returns a list of byte arrays, one per signal (0-indexed).
  /// Each byte array contains the encoded value change chain for that signal.
  /// Changes at [blockStartTime] are skipped (captured in the frame).
  List<Uint8List> _buildSignalData(
    Map<int, int> timeToIndex,
    int blockStartTime,
  ) {
    // Group changes by signal handle index
    final signalChanges = List<List<_ValueChange>>.generate(
      _signals.length,
      (_) => [],
    );
    for (final c in _changes) {
      // Skip changes at blockStartTime — those are captured in the frame
      if (c.time == blockStartTime) {
        continue;
      }
      signalChanges[c.handleIndex].add(c);
    }

    final result = <Uint8List>[];
    for (var sigIdx = 0; sigIdx < _signals.length; sigIdx++) {
      final changes = signalChanges[sigIdx];
      if (changes.isEmpty) {
        result.add(Uint8List(0));
        continue;
      }

      final sig = _signals[sigIdx];
      final buf = BytesBuilder(copy: false);
      var prevTimeIndex = 0;

      for (final c in changes) {
        final timeIndex = timeToIndex[c.time]!;
        final timeDelta = timeIndex - prevTimeIndex;
        prevTimeIndex = timeIndex;

        if (sig.frameLength == 1) {
          // 1-bit signal: compact encoding
          buf.add(_encodeOneBitChange(timeDelta, c.value));
        } else if (sig.isReal) {
          // Real signal
          buf.add(_encodeRealChange(timeDelta, c.value));
        } else {
          // Multi-bit signal
          buf.add(_encodeMultiBitChange(timeDelta, c.value, sig.width));
        }
      }
      result.add(buf.toBytes());
    }
    return result;
  }

  /// Encodes a 1-bit signal value change.
  ///
  /// Format: varint where:
  /// - Normal (0/1): bit0=0, bit1=value, bits2+= time_index_delta
  /// - Special (x/z/etc): bit0=1, bits1-3=rcv_index, bits4+=time_index_delta
  Uint8List _encodeOneBitChange(int timeDelta, String value) {
    // RCV_STR: [x, z, h, u, w, l, -, ?]
    const rcvChars = 'xzhuwl-?';
    final ch = value.isNotEmpty ? value[value.length - 1] : 'x';

    int vli;
    if (ch == '0') {
      vli = (timeDelta << 2) | (0 << 1) | 0; // bit0=0, bit1=0
    } else if (ch == '1') {
      vli = (timeDelta << 2) | (1 << 1) | 0; // bit0=0, bit1=1
    } else {
      final rcvIdx = rcvChars.indexOf(ch);
      final idx = rcvIdx >= 0 ? rcvIdx : 0; // default to 'x'
      vli = (timeDelta << 4) | (idx << 1) | 1; // bit0=1, bits1-3=idx
    }
    return encodeVarint(vli);
  }

  /// Encodes a multi-bit signal value change.
  ///
  /// Format: varint(time_delta << 1 | encoding_bit) then value bytes.
  /// encoding_bit=0: 2-state packed bits; encoding_bit=1: 4-state characters.
  Uint8List _encodeMultiBitChange(int timeDelta, String value, int width) {
    final buf = BytesBuilder(copy: false);

    // Check if value contains only 0/1 (2-state)
    final is2State = value.runes.every((c) => c == 0x30 || c == 0x31);

    if (is2State) {
      // 2-state: pack bits into bytes, MSB first
      buf.add(encodeVarint((timeDelta << 1) | 0));
      final byteCount = (width + 7) ~/ 8;
      final bytes = Uint8List(byteCount);
      for (var i = 0; i < width; i++) {
        if (i < value.length && value[i] == '1') {
          final byteIdx = i ~/ 8;
          final bitIdx = 7 - (i % 8);
          bytes[byteIdx] |= 1 << bitIdx;
        }
      }
      buf.add(bytes);
    } else {
      // 4-state: raw character bytes
      buf.add(encodeVarint((timeDelta << 1) | 1));
      for (var i = 0; i < width; i++) {
        buf.addByte(i < value.length ? value.codeUnitAt(i) : 0x78);
      }
    }
    return buf.toBytes();
  }

  /// Encodes a real signal value change.
  Uint8List _encodeRealChange(int timeDelta, String value) {
    final buf = BytesBuilder(copy: false)
      ..add(encodeVarint((timeDelta << 1) | 1));
    final d = double.tryParse(value) ?? 0.0;
    final bd = ByteData(8)..setFloat64(0, d, Endian.little);
    buf.add(bd.buffer.asUint8List());
    return buf.toBytes();
  }

  /// Builds the offset chain for DynamicAlias2 format.
  ///
  /// The chain encodes the byte offset and presence of each signal's
  /// packed data within the value change section.
  Uint8List _buildOffsetChain(List<Uint8List> packedSignals) {
    final buf = BytesBuilder(copy: false);
    var currentOffset = 0; // byte offset within vc section (after pack_type)
    var prevOffset = 0;
    var consecutiveEmpty = 0;

    // Offset 0 is the pack_type byte itself. Signal data starts at offset 1.
    currentOffset = 1; // skip the pack_type byte

    for (var i = 0; i < packedSignals.length; i++) {
      final ps = packedSignals[i];
      if (ps.isEmpty) {
        consecutiveEmpty++;
      } else {
        // Flush any consecutive empty signals
        if (consecutiveEmpty > 0) {
          // Write: varint((count << 1) | 0)  — bit0=0 means "zero block"
          buf.add(encodeVarint(consecutiveEmpty << 1));
          consecutiveEmpty = 0;
        }
        // Write positive offset delta (signed varint with bit0=1)
        // In DynamicAlias2: bit0=1 + signed_varint >> 1 > 0 means
        // new incremental offset delta.
        // Encoding: signed_varint((delta << 1) | 1)
        // Reader does: shval = read_variant_i64() >> 1 = delta
        final offsetDelta = currentOffset - prevOffset;
        buf.add(encodeSignedVarint((offsetDelta << 1) | 1));
        prevOffset = currentOffset;
        currentOffset += ps.length;
      }
    }

    // Flush trailing empty signals
    if (consecutiveEmpty > 0) {
      buf.add(encodeVarint(consecutiveEmpty << 1));
    }

    return buf.toBytes();
  }

  /// Builds the time table section (appended at end of VcData block).
  ///
  /// The time table is: compressed delta-encoded timestamps, followed by
  /// 3 u64s: uncompressed_length, compressed_length, num_entries.
  Uint8List _buildTimeTableBytes(List<int> timeTable) {
    // Delta-encode the time table
    final deltaBuf = BytesBuilder(copy: false);
    var prevTime = 0;
    for (final t in timeTable) {
      deltaBuf.add(encodeVarint(t - prevTime));
      prevTime = t;
    }
    final uncompressed = deltaBuf.toBytes();
    final compressed = _zlibCompress(
      uncompressed,
      config.compressionLevel,
      allowRaw: true,
    );

    // Build the full time section: compressed data + 3 u64s
    final result = BytesBuilder(copy: false)
      ..add(compressed)
      ..add(_encodeU64(uncompressed.length))
      ..add(_encodeU64(compressed.length))
      ..add(_encodeU64(timeTable.length));
    return result.toBytes();
  }

  // ─────────────── Low-level I/O helpers ───────────────

  /// Writes a big-endian u64.
  void _writeU64(int value) {
    final bd = ByteData(8)..setUint64(0, value);
    _file.writeFromSync(bd.buffer.asUint8List());
  }

  /// Encodes a big-endian u64 to bytes.
  Uint8List _encodeU64(int value) {
    final bd = ByteData(8)..setUint64(0, value);
    return bd.buffer.asUint8List();
  }

  /// Writes a little-endian f64 (for double endian test).
  void _writeF64LE(double value) {
    final bd = ByteData(8)..setFloat64(0, value, Endian.little);
    _file.writeFromSync(bd.buffer.asUint8List());
  }

  /// Writes a fixed-length NUL-padded string.
  void _writeFixedString(String value, int maxLen) {
    final bytes = utf8.encode(value);
    final len = bytes.length < maxLen ? bytes.length : maxLen - 1;
    _file
      ..writeFromSync(bytes.sublist(0, len))
      // Pad with zeros
      ..writeFromSync(Uint8List(maxLen - len));
  }

  /// Encodes a NUL-terminated string.
  Uint8List _cString(String value) {
    final bytes = utf8.encode(value);
    final result = Uint8List(bytes.length + 1)
      ..setRange(0, bytes.length, bytes);
    // last byte is already 0
    return result;
  }

  /// Encodes an unsigned integer as LEB128 varint.
  static Uint8List encodeVarint(int value) {
    if (value < 0) {
      throw ArgumentError('Value must be non-negative: $value');
    }
    if (value <= 0x7F) {
      return Uint8List.fromList([value]);
    }
    final bytes = <int>[];
    var v = value;
    while (v != 0) {
      final nextV = v >> 7;
      final mask = nextV == 0 ? 0 : 0x80;
      bytes.add((v & 0x7F) | mask);
      v = nextV;
    }
    return Uint8List.fromList(bytes);
  }

  /// Encodes a signed integer as signed LEB128 varint.
  static Uint8List encodeSignedVarint(int value) {
    if (value >= -64 && value <= 63) {
      return Uint8List.fromList([value & 0x7F]);
    }

    final bytes = <int>[];
    var v = value;
    var more = true;
    while (more) {
      var byte_ = v & 0x7F;
      v >>= 7;
      // Check if we're done
      if ((v == 0 && (byte_ & 0x40) == 0) || (v == -1 && (byte_ & 0x40) != 0)) {
        more = false;
      } else {
        byte_ |= 0x80;
      }
      bytes.add(byte_);
    }
    return Uint8List.fromList(bytes);
  }

  /// Writes gzip-compressed bytes (gzip header + deflate data).
  void _writeGzipCompressed(Uint8List data) {
    // Gzip header (10 bytes)
    const gzipHeader = <int>[
      0x1F, 0x8B, // magic
      0x08, // deflate
      0x00, // no flags
      0x00, 0x00, 0x00, 0x00, // timestamp = 0
      0x00, // compression level
      0xFF, // OS = unknown
    ];
    _file.writeFromSync(Uint8List.fromList(gzipHeader));

    // Deflate-compressed data (raw deflate, not zlib-wrapped)
    final compressed = _deflateCompress(data, config.compressionLevel);
    _file.writeFromSync(compressed);
  }

  /// Compresses bytes using zlib (with zlib header, for geometry/frame/etc).
  static Uint8List _zlibCompress(
    Uint8List data,
    int level, {
    bool allowRaw = false,
  }) {
    final compressed = ZLibCodec(level: level).encode(data);
    final result = Uint8List.fromList(compressed);
    if (allowRaw && result.length >= data.length) {
      // Compression didn't help, return uncompressed
      return data;
    }
    return result;
  }

  /// Compresses bytes using raw deflate (no zlib header, for gzip hierarchy).
  static Uint8List _deflateCompress(Uint8List data, int level) {
    final compressed = ZLibCodec(level: level, raw: true).encode(data);
    return Uint8List.fromList(compressed);
  }

  /// Generates a date string for the header.
  String _dateString() {
    final now = DateTime.now();
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
    ];
    final day = days[now.weekday - 1];
    final month = months[now.month - 1];
    final d = now.day.toString().padLeft(2);
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    return '$day $month $d $h:$m:$s ${now.year}\n';
  }
}
