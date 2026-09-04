// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// fst_block_reader.dart
// Lightweight companion reader for FstWriter that reads back VcData blocks
// from disk using the writer's block index.
//
// This is NOT a general-purpose FST reader. For full FST file reading
// (post-simulation), use the wellen library via the rohd-wave-viewer's
// dart_wellen package which wraps the Rust fst-reader crate.
//
// 2026 February
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:io';
import 'dart:typed_data';

import 'package:rohd/src/fst/fst_writer.dart';

/// A value change record decoded from an FST VcData block.
class FstValueChange {
  /// The simulation timestamp.
  final int time;

  /// The signal value as a string.
  final String value;

  /// Creates a decoded value change.
  const FstValueChange(this.time, this.value);

  @override
  String toString() => 'FstValueChange(t=$time, v=$value)';
}

/// Lightweight reader that decodes VcData DynamicAlias2 blocks written by
/// [FstWriter].
///
/// Uses the [FstWriter.blockIndex] to locate blocks on disk and reads only
/// the requested signals, avoiding loading the entire FST file into memory.
///
/// ## Architecture
///
/// During a live simulation the data flow is:
///
/// ```dart
/// FstWriter  ──(flushBlock)──>  .fst file (VcData blocks on disk)
///                                   │
/// FstBlockReader ────(readBlock)────┘
///                                   │
/// WaveformDataService  <──(merge)──── disk data + hot buffer
///     │
///     └──(VM Service extensions)──> DevTools extension
/// ```
///
/// Post-simulation, the finalized `.fst` file can be read by the **wellen**
/// library (Rust, via `dart_wellen`) in the rohd-wave-viewer for full
/// waveform browsing.
class FstBlockReader {
  /// Signal metadata from the writer (indexed by handle - 1).
  final List<FstSignalInfo> _signals;

  /// Path to the FST file on disk.
  final String filePath;

  /// Creates a block reader for the FST file at [filePath].
  ///
  /// [signals] must match the signals declared in the associated [FstWriter].
  /// The reader opens its own file handle for each read, so it is safe to use
  /// after the writer has been finished or closed.
  FstBlockReader(this.filePath, List<FstSignalInfo> signals)
      : _signals = List.unmodifiable(signals);

  /// Reads a single VcData block and returns value changes for the
  /// specified signal handles.
  ///
  /// [block] identifies which block to read (from [FstWriter.blockIndex]).
  /// [handleIndices] are the 0-based signal indices to extract.
  /// If [startTime] / [endTime] are provided, only changes within that
  /// range are returned.
  ///
  /// Returns a map from handle index to a list of value changes.
  Map<int, List<FstValueChange>> readBlock(
    FstBlockIndex block, {
    Set<int>? handleIndices,
    int? startTime,
    int? endTime,
  }) {
    final file = File(filePath).openSync();
    try {
      return _readBlockImpl(
        file,
        block,
        handleIndices: handleIndices,
        startTime: startTime,
        endTime: endTime,
      );
    } finally {
      file.closeSync();
    }
  }

  /// Read the frame (initial values at block start) for all signals.
  ///
  /// Returns a list indexed by handle (0-based) of initial value strings.
  List<String> readBlockFrame(FstBlockIndex block) {
    final file = File(filePath).openSync();
    try {
      return _readFrameImpl(file, block);
    } finally {
      file.closeSync();
    }
  }

  // ─────────────── Implementation ───────────────

  Map<int, List<FstValueChange>> _readBlockImpl(
    RandomAccessFile file,
    FstBlockIndex block, {
    Set<int>? handleIndices,
    int? startTime,
    int? endTime,
  }) {
    // The block layout (DynamicAlias2):
    //   block_type(1) + section_length(8) + start_time(8) + end_time(8)
    //   + mem_required(8) = 33 bytes of header
    //   Then: frame, vc data, offset chain, time table
    //
    // We read from the end backwards to get time table first,
    // then offset chain, then signal data.

    final sectionStart = block.fileOffset + 1; // after block_type byte
    final sectionEnd = sectionStart + block.sectionLength;

    // 1. Read the time table (last 24 bytes of section)
    final timeTable = _readTimeTable(file, sectionStart, sectionEnd);

    // 2. Locate the offset chain
    //    Last 24 bytes: time_uncomp(8), time_comp(8), time_items(8)
    final timeTableMetaStart = sectionEnd - 24;
    file.setPositionSync(timeTableMetaStart + 8);
    final compressedTimeLen = _readU64(file);
    final timeDataStart = timeTableMetaStart - compressedTimeLen;

    // chain_compressed_length is 8 bytes before time data
    final chainLenOffset = timeDataStart - 8;
    file.setPositionSync(chainLenOffset);
    final chainLen = _readU64(file);

    // 3. Read the offset chain bytes
    final chainStart = chainLenOffset - chainLen;
    file.setPositionSync(chainStart);
    final chainBytes = file.readSync(chainLen);

    // 4. Read frame and VC header to find signal data positions
    //    Skip: section_length(8) + start_time(8) + end_time(8) + mem(8)
    file.setPositionSync(sectionStart + 32);
    final frameUncLen = _readVarint(file);
    final frameCompLen = _readVarint(file);
    _readVarint(file); // maxHandle
    final frameDataStart = file.positionSync();
    file.setPositionSync(frameDataStart + frameCompLen);

    // VC header: max_handle varint + pack_type byte
    _readVarint(file); // vcMaxHandle
    final vcBase = file.positionSync(); // position of pack_type byte
    final packType = file.readSync(1)[0];
    // Signal data starts at vcBase + 1 (offset 1 in writer's scheme)

    // Read and decompress the frame
    file.setPositionSync(frameDataStart);
    final frameCompressed = file.readSync(frameCompLen);
    final frameBytes = (frameCompLen == frameUncLen)
        ? Uint8List.fromList(frameCompressed)
        : _zlibDecompress(Uint8List.fromList(frameCompressed));
    final frameValues = _decodeFrame(frameBytes);

    // 5. Parse offset chain to get signal data locations
    //    Offsets are relative to vcBase (pack_type position).
    //    Signal data section ends at chainStart.
    final signalDataEndRel = chainStart - vcBase;
    final signalLocations = _parseOffsetChain(
      chainBytes,
      _signals.length,
      signalDataEndRel,
    );

    // 6. Decode each requested signal
    final result = <int, List<FstValueChange>>{};
    final requestedHandles = handleIndices ??
        Set<int>.from(List.generate(_signals.length, (i) => i));

    for (final handleIdx in requestedHandles) {
      if (handleIdx < 0 || handleIdx >= _signals.length) {
        continue;
      }

      final loc = signalLocations[handleIdx];
      if (loc == null) {
        // No data for this signal in this block — use frame value
        if ((startTime == null || block.startTime >= startTime) &&
            (endTime == null || block.startTime <= endTime)) {
          result[handleIdx] = [
            FstValueChange(block.startTime, frameValues[handleIdx]),
          ];
        } else {
          result[handleIdx] = [];
        }
        continue;
      }

      // Read the packed signal data (offset relative to vcBase)
      file.setPositionSync(vcBase + loc.offset);
      final packedData = file.readSync(loc.length);

      // Unpack: varint prefix indicates compression
      final unpacked = _unpackSignalData(
        Uint8List.fromList(packedData),
        packType,
      );

      // Decode value changes using the time table
      final sig = _signals[handleIdx];
      final changes = _decodeSignalChanges(
        unpacked,
        sig,
        timeTable,
        startTime: startTime,
        endTime: endTime,
      );

      // Prepend frame value at block start time if in range
      final allChanges = <FstValueChange>[];
      if ((startTime == null || block.startTime >= startTime) &&
          (endTime == null || block.startTime <= endTime)) {
        allChanges.add(FstValueChange(block.startTime, frameValues[handleIdx]));
      }
      allChanges.addAll(changes);
      result[handleIdx] = allChanges;
    }

    return result;
  }

  List<String> _readFrameImpl(RandomAccessFile file, FstBlockIndex block) {
    final sectionStart = block.fileOffset + 1;
    file.setPositionSync(sectionStart + 32);
    final frameUncLen = _readVarint(file);
    final frameCompLen = _readVarint(file);
    _readVarint(file); // maxHandle
    final frameCompressed = file.readSync(frameCompLen);
    final frameBytes = (frameCompLen == frameUncLen)
        ? Uint8List.fromList(frameCompressed)
        : _zlibDecompress(Uint8List.fromList(frameCompressed));
    return _decodeFrame(frameBytes);
  }

  // ─────────────── Time table decoding ───────────────

  /// Reads the time table from the end of a VcData section.
  List<int> _readTimeTable(
    RandomAccessFile file,
    int sectionStart,
    int sectionEnd,
  ) {
    file.setPositionSync(sectionEnd - 24);
    final uncLen = _readU64(file);
    final compLen = _readU64(file);
    final numItems = _readU64(file);

    final timeDataOffset = sectionEnd - 24 - compLen;
    file.setPositionSync(timeDataOffset);
    final compressedData = file.readSync(compLen);

    final Uint8List uncompressed;
    if (compLen == uncLen) {
      uncompressed = Uint8List.fromList(compressedData);
    } else {
      uncompressed = _zlibDecompress(Uint8List.fromList(compressedData));
    }

    final timeTable = <int>[];
    var offset = 0;
    var prevTime = 0;
    for (var i = 0; i < numItems; i++) {
      final (delta, newOffset) = _decodeVarintFromBytes(uncompressed, offset);
      offset = newOffset;
      prevTime += delta;
      timeTable.add(prevTime);
    }
    return timeTable;
  }

  // ─────────────── Offset chain parsing ───────────────

  /// Parses the DynamicAlias2 offset chain to locate each signal's data.
  ///
  /// [signalDataEndRel] is the byte offset (relative to vcBase) where
  /// signal data ends (i.e., the chain start position).
  Map<int, _SignalLoc?> _parseOffsetChain(
    Uint8List chainBytes,
    int signalCount,
    int signalDataEndRel,
  ) {
    final locs = <int, _SignalLoc?>{};
    var offset = 0;
    var handleIdx = 0;
    var currentOffset = 0;
    final offsets = <int, int>{};

    while (offset < chainBytes.length && handleIdx < signalCount) {
      final firstByte = chainBytes[offset];

      if ((firstByte & 1) == 1) {
        final (raw, newOffset) = _decodeSignedVarintFromBytes(
          chainBytes,
          offset,
        );
        offset = newOffset;
        final shval = raw >> 1;

        if (shval > 0) {
          currentOffset += shval;
          offsets[handleIdx] = currentOffset;
          handleIdx++;
        } else if (shval < 0) {
          locs[handleIdx] = null; // alias
          handleIdx++;
        } else {
          locs[handleIdx] = null; // same alias
          handleIdx++;
        }
      } else {
        final (raw, newOffset) = _decodeVarintFromBytes(chainBytes, offset);
        offset = newOffset;
        final zeros = raw >> 1;
        for (var i = 0; i < zeros && handleIdx < signalCount; i++) {
          locs[handleIdx] = null;
          handleIdx++;
        }
      }
    }

    while (handleIdx < signalCount) {
      locs[handleIdx] = null;
      handleIdx++;
    }

    // Compute lengths from consecutive offsets
    final sortedHandles = offsets.keys.toList()..sort();
    for (var i = 0; i < sortedHandles.length; i++) {
      final h = sortedHandles[i];
      final start = offsets[h]!;
      final end = (i + 1 < sortedHandles.length)
          ? offsets[sortedHandles[i + 1]]!
          : signalDataEndRel;
      locs[h] = _SignalLoc(start, end - start);
    }

    return locs;
  }

  // ─────────────── Frame decoding ───────────────

  /// Decodes frame bytes back to string values, one per signal.
  List<String> _decodeFrame(Uint8List frameBytes) {
    final result = <String>[];
    var offset = 0;

    for (final sig in _signals) {
      if (sig.isReal) {
        if (offset + 8 <= frameBytes.length) {
          final bd = ByteData.sublistView(frameBytes, offset, offset + 8);
          final d = bd.getFloat64(0, Endian.little);
          result.add(d.toString());
        } else {
          result.add('0.0');
        }
        offset += 8;
      } else {
        final width = sig.width;
        final buf = StringBuffer();
        for (var j = 0; j < width; j++) {
          if (offset + j < frameBytes.length) {
            buf.writeCharCode(frameBytes[offset + j]);
          } else {
            buf.write('x');
          }
        }
        result.add(buf.toString());
        offset += width;
      }
    }
    return result;
  }

  // ─────────────── Signal data decoding ───────────────

  /// Unpacks a signal's data: reads the varint(uncomp_len) prefix and
  /// decompresses if needed.
  Uint8List _unpackSignalData(Uint8List packedData, int packType) {
    if (packedData.isEmpty) {
      return Uint8List(0);
    }

    var offset = 0;
    final (uncLen, newOffset) = _decodeVarintFromBytes(packedData, offset);
    offset = newOffset;

    final payload = packedData.sublist(offset);
    if (uncLen == 0) {
      // Raw/uncompressed (writer stores varint(0) prefix for raw data)
      return Uint8List.fromList(payload);
    }

    // Compressed — decompress
    return _zlibDecompress(Uint8List.fromList(payload));
  }

  /// Decodes value changes from a signal's uncompressed data stream.
  List<FstValueChange> _decodeSignalChanges(
    Uint8List data,
    FstSignalInfo sig,
    List<int> timeTable, {
    int? startTime,
    int? endTime,
  }) {
    if (data.isEmpty) {
      return [];
    }

    final changes = <FstValueChange>[];
    var offset = 0;
    var timeIdx = 0;

    while (offset < data.length) {
      if (sig.width == 1 && !sig.isReal) {
        // 1-bit signal
        final (vli, newOffset) = _decodeVarintFromBytes(data, offset);
        offset = newOffset;

        String value;
        int timeDelta;
        if ((vli & 1) == 0) {
          value = ((vli >> 1) & 1) == 0 ? '0' : '1';
          timeDelta = vli >> 2;
        } else {
          const rcvChars = 'xzhuwl-?';
          final rcvIdx = (vli >> 1) & 7;
          value = rcvIdx < rcvChars.length ? rcvChars[rcvIdx] : 'x';
          timeDelta = vli >> 4;
        }
        timeIdx += timeDelta;
        if (timeIdx < timeTable.length) {
          final t = timeTable[timeIdx];
          if ((startTime == null || t >= startTime) &&
              (endTime == null || t <= endTime)) {
            changes.add(FstValueChange(t, value));
          }
        }
      } else if (sig.isReal) {
        // Real signal
        final (vli, newOffset) = _decodeVarintFromBytes(data, offset);
        offset = newOffset;
        final timeDelta = vli >> 1;
        timeIdx += timeDelta;

        if (offset + 8 <= data.length) {
          final bd = ByteData.sublistView(data, offset, offset + 8);
          final d = bd.getFloat64(0, Endian.little);
          offset += 8;
          if (timeIdx < timeTable.length) {
            final t = timeTable[timeIdx];
            if ((startTime == null || t >= startTime) &&
                (endTime == null || t <= endTime)) {
              changes.add(FstValueChange(t, d.toString()));
            }
          }
        } else {
          break;
        }
      } else {
        // Multi-bit signal
        final (vli, newOffset) = _decodeVarintFromBytes(data, offset);
        offset = newOffset;
        final timeDelta = vli >> 1;
        final is4State = (vli & 1) == 1;
        timeIdx += timeDelta;

        String value;
        if (!is4State) {
          final byteCount = (sig.width + 7) ~/ 8;
          if (offset + byteCount > data.length) {
            break;
          }
          final buf = StringBuffer();
          for (var i = 0; i < sig.width; i++) {
            final byteIdx = i ~/ 8;
            final bitIdx = 7 - (i % 8);
            final bit = (data[offset + byteIdx] >> bitIdx) & 1;
            buf.write(bit == 0 ? '0' : '1');
          }
          value = buf.toString();
          offset += byteCount;
        } else {
          if (offset + sig.width > data.length) {
            break;
          }
          value = String.fromCharCodes(data, offset, offset + sig.width);
          offset += sig.width;
        }

        if (timeIdx < timeTable.length) {
          final t = timeTable[timeIdx];
          if ((startTime == null || t >= startTime) &&
              (endTime == null || t <= endTime)) {
            changes.add(FstValueChange(t, value));
          }
        }
      }
    }

    return changes;
  }

  // ─────────────── Low-level I/O helpers ───────────────

  /// Reads a big-endian u64 from [file] at the current position.
  static int _readU64(RandomAccessFile file) {
    final bytes = file.readSync(8);
    final bd = ByteData.sublistView(Uint8List.fromList(bytes));
    return bd.getUint64(0);
  }

  /// Reads an unsigned LEB128 varint from [file] at the current position.
  static int _readVarint(RandomAccessFile file) {
    var result = 0;
    var shift = 0;
    while (true) {
      final byte = file.readSync(1)[0];
      result |= (byte & 0x7F) << shift;
      if ((byte & 0x80) == 0) {
        break;
      }
      shift += 7;
    }
    return result;
  }

  /// Decodes an unsigned LEB128 varint from [bytes] at [offset].
  static (int, int) _decodeVarintFromBytes(Uint8List bytes, int offset) {
    var result = 0;
    var shift = 0;
    var pos = offset;
    while (pos < bytes.length) {
      final byte = bytes[pos++];
      result |= (byte & 0x7F) << shift;
      if ((byte & 0x80) == 0) {
        break;
      }
      shift += 7;
    }
    return (result, pos);
  }

  /// Decodes a signed LEB128 varint from [bytes] at [offset].
  static (int, int) _decodeSignedVarintFromBytes(Uint8List bytes, int offset) {
    var result = 0;
    var shift = 0;
    var pos = offset;
    int byte;
    do {
      byte = bytes[pos++];
      result |= (byte & 0x7F) << shift;
      shift += 7;
    } while ((byte & 0x80) != 0 && pos < bytes.length);

    if (shift < 64 && (byte & 0x40) != 0) {
      result |= ~0 << shift;
    }
    return (result, pos);
  }

  /// Decompresses zlib-compressed data.
  static Uint8List _zlibDecompress(Uint8List data) {
    final decompressed = ZLibCodec().decode(data);
    return Uint8List.fromList(decompressed);
  }
}

/// Internal: location of a signal's data within the VC section.
class _SignalLoc {
  /// Byte offset relative to vcBase (pack_type byte position).
  final int offset;

  /// Length in bytes.
  final int length;

  const _SignalLoc(this.offset, this.length);
}
