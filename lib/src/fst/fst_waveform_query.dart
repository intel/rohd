// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// fst_waveform_query.dart
// Live, bounded-memory queries over FST writer output.

import 'package:rohd/src/fst/fst_block_reader.dart';
import 'package:rohd/src/fst/fst_writer.dart';

/// Queries an [FstWriter]'s flushed blocks and unflushed hot buffer.
///
/// This provider does not own the writer. It may be used while simulation is
/// running, after [FstWriter.flushBlock] has moved historical changes to disk,
/// or after the writer has finished.
class FstWaveformQuery {
  /// Creates a query provider for a writer whose signals have been declared.
  FstWaveformQuery(this.writer)
      : _reader = FstBlockReader(writer.filePath, writer.signalInfoList);

  /// The writer supplying the indexed disk blocks and hot buffer.
  final FstWriter writer;

  final FstBlockReader _reader;

  /// Returns all value changes for [signal] within the inclusive time range.
  ///
  /// Results merge matching flushed blocks with the writer's unflushed changes
  /// and are ordered by timestamp.
  List<FstValueChange> changes(
    FstSignalHandle signal, {
    required int startTime,
    required int endTime,
  }) {
    if (startTime > endTime) {
      throw ArgumentError.value(
        endTime,
        'endTime',
        'must be greater than or equal to startTime',
      );
    }

    final handleIndex = signal.handle - 1;
    _validateHandle(handleIndex);
    final result = <FstValueChange>[];
    for (final block in writer.blockIndex) {
      if (block.endTime < startTime || block.startTime > endTime) {
        continue;
      }
      result.addAll(
        _reader.readBlock(
              block,
              handleIndices: {handleIndex},
              startTime: startTime,
              endTime: endTime,
            )[handleIndex] ??
            const [],
      );
    }
    result.addAll(
      writer
          .queryHotBuffer(handleIndex, startTime, endTime)
          .map((change) => FstValueChange(change.time, change.value)),
    );
    result.sort((a, b) => a.time.compareTo(b.time));
    return result;
  }

  /// Returns [signal]'s value at or immediately before [time].
  ///
  /// Returns `null` when the writer has not emitted a value for [signal].
  String? valueAt(FstSignalHandle signal, int time) {
    final handleIndex = signal.handle - 1;
    _validateHandle(handleIndex);

    final hotChanges = writer.queryHotBuffer(handleIndex, 0, time);
    if (hotChanges.isNotEmpty) {
      return hotChanges.last.value;
    }

    final blocks = writer.blockIndex;
    for (var index = blocks.length - 1; index >= 0; index--) {
      final block = blocks[index];
      if (block.startTime > time) {
        continue;
      }
      final changes = _reader.readBlock(
        block,
        handleIndices: {handleIndex},
        endTime: time,
      )[handleIndex];
      if (changes != null && changes.isNotEmpty) {
        return changes.last.value;
      }
      return _reader.readBlockFrame(block)[handleIndex];
    }
    return null;
  }

  void _validateHandle(int handleIndex) {
    if (handleIndex < 0 || handleIndex >= writer.signalCount) {
      throw RangeError.index(handleIndex, writer.signalInfoList, 'signal');
    }
  }
}
