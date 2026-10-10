// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// typed_logic_value_array_test.dart
// Tests for typed logic value arrays.
//
// 2026 September 16
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

int _decodeLogicValue(LogicValue value) => value.toInt();

int _decodeEquivalentLogicValue(LogicValue value) => value.toInt();

LogicValue _encodeLogicValue(int value) => LogicValue.ofInt(value, 8);

double _decodeRoundedLogicValue(LogicValue value) => value.toInt().toDouble();

LogicValue _encodeRoundedLogicValue(double value) =>
    LogicValue.ofInt(value.round(), 8);

List<int> _decodeListLogicValue(LogicValue value) => [value.toInt()];

LogicValue _encodeListLogicValue(List<int> value) =>
    LogicValue.ofInt(value.single, 8);

void main() {
  group('TypedLogicValueArray', () {
    test('rejects empty and non-semantic nested input', () {
      const codec = LogicValueCodec<int>(
        decode: _decodeLogicValue,
        encode: _encodeLogicValue,
      );

      expect(
        () => TypedLogicValueArray<int>(const [], codec: codec),
        throwsArgumentError,
      );
      expect(
        () => TypedLogicValueArray<int>(
          const [
            1,
            'not an integer',
          ],
          codec: codec,
        ),
        throwsArgumentError,
      );
    });

    test('constructs equivalent nested and flat list-valued data', () {
      const codec = LogicValueCodec<List<int>>(
        decode: _decodeListLogicValue,
        encode: _encodeListLogicValue,
      );
      final leaves = [
        [1],
        [2],
        [3],
        [4],
      ];
      final nested = TypedLogicValueArray<List<int>>([
        [leaves[0], leaves[1]],
        [leaves[2], leaves[3]],
      ], codec: codec);
      final flat = TypedLogicValueArray<List<int>>.fromFlat(
        const [2, 2],
        8,
        leaves,
        codec: codec,
      );

      expect(nested.dimensions, [2, 2]);
      expect(flat.dimensions, nested.dimensions);
      expect(nested.arrayValues.map((value) => value.single), [1, 2, 3, 4]);
      expect(flat.arrayValues.map((value) => value.single), [1, 2, 3, 4]);
      expect(nested.at([1, 0]), [3]);
      expect(flat.packed, nested.packed);
    });

    test('maps, reshapes, transposes, and converts typed values', () {
      const codec = LogicValueCodec<int>(
        decode: _decodeLogicValue,
        encode: _encodeLogicValue,
      );
      final packed = LogicValueArray.fromInts(const [
        [1, 2, 3],
        [4, 5, 6],
      ], elementWidth: 8);
      final values = TypedLogicValueArray<int>.fromLogicValueArray(
        packed,
        codec: codec,
      );

      expect(values.at([1, 1]), 5);
      expect(values.map((value) => value + 1).at([1, 1]), 6);
      expect(values.reshape([3, 2]).at([2, 1]), 6);
      expect(values.transpose2D().arrayValues, [1, 4, 2, 5, 3, 6]);
      final signals = values.toLogicArray();
      expect(signals.dimensions, [2, 3]);
      expect(signals.value, values);
    });

    test('supports slices, indexed mapping, and compatible stacking', () {
      const codec = LogicValueCodec<int>(
        decode: _decodeLogicValue,
        encode: _encodeLogicValue,
      );
      final values = TypedLogicValueArray<int>(const [
        [1, 2],
        [3, 4],
      ], codec: codec);

      expect(values.majorSlices.map((slice) => slice.arrayValues), [
        [1, 2],
        [3, 4],
      ]);
      expect(
        values.indexedMap((indices, value) => value + indices[1]).arrayValues,
        [1, 3, 3, 5],
      );
      expect(
        TypedLogicValueArray<int>.stack(values.majorSlices).arrayValues,
        values.arrayValues,
      );
      expect(values.packed, LogicValue.ofInt(0x04030201, 32));
    });

    test('normalizes lossy codecs at construction and preserves values', () {
      const codec = LogicValueCodec<double>(
        decode: _decodeRoundedLogicValue,
        encode: _encodeRoundedLogicValue,
      );
      final values = TypedLogicValueArray<double>(const [
        [1.2, 2.4],
        [3.6, 4.8],
      ], codec: codec);

      expect(values.arrayValues, [1.0, 2.0, 4.0, 5.0]);
      expect(values.reshape([4]).arrayValues, values.arrayValues);
      expect(
        TypedLogicValueArray<double>.stack(values.majorSlices).arrayValues,
        values.arrayValues,
      );
      expect(values.transpose2D().arrayValues, [1.0, 4.0, 2.0, 5.0]);
    });

    test('requires identical codecs when stacking', () {
      const firstCodec = LogicValueCodec<int>(
        decode: _decodeLogicValue,
        encode: _encodeLogicValue,
      );
      const secondCodec = LogicValueCodec<int>(
        decode: _decodeEquivalentLogicValue,
        encode: _encodeLogicValue,
      );
      final first = TypedLogicValueArray<int>.fromFlat(
        const [1],
        8,
        const [1],
        codec: firstCodec,
      );
      final second = TypedLogicValueArray<int>.fromFlat(
        const [1],
        8,
        const [2],
        codec: secondCodec,
      );

      expect(
        () => TypedLogicValueArray<int>.stack([first, second]),
        throwsArgumentError,
      );
    });

    test('round-trips typed slices with an empty inner dimension', () {
      const codec = LogicValueCodec<int>(
        decode: _decodeLogicValue,
        encode: _encodeLogicValue,
      );
      final values = TypedLogicValueArray<int>.fromFlat(
        const [2, 0],
        8,
        const [],
        codec: codec,
      );
      final slices = values.majorSlices.toList(growable: false);

      expect(slices, hasLength(2));
      expect(slices.map((slice) => slice.dimensions), [
        [0],
        [0],
      ]);
      expect(
        TypedLogicValueArray<int>.stack(slices).dimensions,
        [2, 0],
      );
    });
  });
}
