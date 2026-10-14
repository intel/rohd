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

  /// Returns emitted values for [signal] within the inclusive time range.
  ///
  /// Results merge matching flushed blocks with the writer's unflushed changes
  /// and are ordered by timestamp. FST block frames carry a value for every
  /// signal, including unchanged signals; those carry-over samples are omitted.
  /// If a signal has multiple emitted values at the same timestamp, only its
  /// final value is returned.
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
      if (block.startTime >= startTime &&
          block.startTime <= endTime &&
          block.changedSignalIndicesAtStart.contains(handleIndex)) {
        result.add(FstValueChange(
          block.startTime,
          _reader.readBlockFrame(block)[handleIndex],
        ));
      }
      result.addAll(
        _reader.readBlock(
              block,
              handleIndices: {handleIndex},
              startTime: startTime,
              endTime: endTime,
              includeFrame: false,
            )[handleIndex] ??
            const [],
      );
    }
    result.addAll(
      writer
          .queryHotBuffer(handleIndex, startTime, endTime)
          .map((change) => FstValueChange(change.time, change.value)),
    );

    final ordered = [
      for (var index = 0; index < result.length; index++)
        (index, result[index]),
    ]..sort((a, b) {
        final timeCmp = a.$2.time.compareTo(b.$2.time);
        return timeCmp != 0 ? timeCmp : a.$1.compareTo(b.$1);
      });

    final coalesced = <FstValueChange>[];
    for (final entry in ordered) {
      final change = entry.$2;
      if (coalesced.isNotEmpty && coalesced.last.time == change.time) {
        coalesced[coalesced.length - 1] = change;
      } else {
        coalesced.add(change);
      }
    }
    return coalesced;
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
