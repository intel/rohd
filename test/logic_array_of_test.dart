// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_array_of_test.dart
// Tests for typed logic and logic value arrays.
//
// 2026 July 21
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class _TwoBitStructure extends LogicStructure {
  final Logic low;
  final Logic high;

  factory _TwoBitStructure({String? name}) => _TwoBitStructure._(
        Logic(name: 'low'),
        Logic(name: 'high'),
        name: name ?? 'twoBit',
      );

  _TwoBitStructure._(this.low, this.high, {required String name})
      : super([low, high], name: name);

  @override
  _TwoBitStructure clone({String? name}) =>
      _TwoBitStructure(name: name ?? this.name);
}

int _decodeLogicValue(LogicValue value) => value.toInt();

LogicValue _encodeLogicValue(int value) => LogicValue.ofInt(value, 8);

void main() {
  group('LogicArrayOf', () {
    test('keeps structured leaves at the array boundary', () {
      final values = LogicArrayOf<_TwoBitStructure>(
        [2, 3],
        _TwoBitStructure.new,
        dimensionNames: const ['row_', 'column_'],
      );

      expect(values, isA<LogicArray>());
      expect(values.dimensions, equals([2, 3]));
      expect(values.elementWidth, 2);
      expect(values.arrayElements, hasLength(6));
      expect(values.typedLeafElements, hasLength(6));
      expect(values.arrayElements, everyElement(isA<_TwoBitStructure>()));
      expect(values.leafElements, hasLength(12));
      expect(values.elementAt([1, 2]), same(values.arrayElements[5]));
      expect(values.indexedElements.last.$1, equals([1, 2]));
    });

    test('provides typed indexing, cloning, and packed conversions', () {
      final values = LogicArrayOf<Logic>(
        [2, 2],
        ({name}) => Logic(name: name, width: 8),
      );
      final packed = values.toLogicArray(name: 'packed');
      final clone = values.clone(name: 'clone');

      expect(values.elementAt([1, 0]), same(values.typedLeafElements[2]));
      expect(packed.dimensions, equals([2, 2]));
      expect(packed.elementWidth, 8);
      expect(clone, isA<LogicArrayOf<Logic>>());
      expect(clone.name, 'clone');
      expect(clone.typedLeafElements, hasLength(4));
      expect(
        () => values.getsPackedValues(LogicArray([4], 8)),
        throwsA(isA<LogicConstructionException>()),
      );
      expect(
        () => values.getsPackedValues(LogicArray([2, 2], 4)),
        throwsA(isA<LogicConstructionException>()),
      );
    });

    test('validates dimensions, names, and leaf widths', () {
      expect(
        () => LogicArrayOf<Logic>(const [], Logic.new),
        throwsA(isA<LogicConstructionException>()),
      );
      expect(
        () => LogicArrayOf<Logic>(
          [2],
          Logic.new,
          dimensionNames: const [],
        ),
        throwsA(isA<LogicConstructionException>()),
      );

      var width = 1;
      expect(
        () => LogicArrayOf<Logic>(
          [2],
          ({name}) => Logic(name: name, width: width++),
        ),
        throwsA(isA<LogicConstructionException>()),
      );
    });

    test('drives and captures compatible packed and typed values', () {
      const codec = LogicValueCodec<int>(
        decode: _decodeLogicValue,
        encode: _encodeLogicValue,
      );
      final values = LogicArrayOf<Logic>(
        [2],
        ({name}) => Logic(name: name, width: 8),
      );
      final packedValues = LogicValueArray.fromInts([2], 8, [12, 34]);
      final typedValues = LogicValueArrayOf<int>(
        [2],
        8,
        [56, 78],
        codec: codec,
      );

      expect(packedValues.putInto(values), same(values));
      expect(
        values.logicValues.flatValues.map((value) => value.toInt()),
        [12, 34],
      );

      values.putValueArrayOf(typedValues);
      expect(values.valueArrayOf(codec).flatValues, [56, 78]);
    });
  });

  group('LogicValueArray', () {
    test('indexes, slices, reshapes, and stacks row-major values', () {
      final values = LogicValueArray.fromInts([2, 3], 8, [1, 2, 3, 4, 5, 6]);

      expect(values.length, 6);
      expect(values.at([1, 1]).toInt(), 5);
      expect(values.flatIndexOf([1, 2]), 5);
      expect(values.indexedValues.last.$1, equals([1, 2]));
      expect(
        values.majorSlices.map(
            (slice) => slice.flatValues.map((value) => value.toInt()).toList()),
        equals([
          [1, 2, 3],
          [4, 5, 6],
        ]),
      );
      expect(values.reshape([3, 2]).at([2, 1]).toInt(), 6);
      expect(
        LogicValueArray.stack(values.majorSlices).dimensions,
        equals([2, 3]),
      );
    });

    test('maps values and validates incompatible operations', () {
      final values = LogicValueArray.fromInts([2, 2], 8, [1, 2, 3, 4]);

      expect(
        values
            .indexedMap((indices, value) =>
                LogicValue.ofInt(value.toInt() + indices[0], 8))
            .flatValues
            .map((value) => value.toInt()),
        equals([1, 2, 4, 5]),
      );
      expect(
        () => values.at([2, 0]),
        throwsA(isA<RangeError>()),
      );
      expect(
        () => values.reshape([3, 2]),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => LogicValueArray.stack([
          values,
          LogicValueArray.fromInts([4], 8, [1, 2, 3, 4]),
        ]),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('LogicValueArrayOf', () {
    test('maps, reshapes, and transposes packed value arrays', () {
      final values = LogicValueArray.fromInts([2, 3], 8, [1, 2, 3, 4, 5, 6]);
      final transposed = values.transpose2D();

      expect(transposed.dimensions, equals([3, 2]));
      expect(
        transposed.flatValues.map((value) => value.toInt()),
        equals([1, 4, 2, 5, 3, 6]),
      );
      expect(values.reshape([3, 2]).at([2, 1]).toInt(), 6);

      const codec = LogicValueCodec<int>(
        decode: _decodeLogicValue,
        encode: _encodeLogicValue,
      );
      final typed = LogicValueArrayOf<int>.fromLogicValues(
        values,
        codec: codec,
      );
      expect(typed.at([1, 1]), 5);
      expect(typed.map((value) => value + 1).at([1, 1]), 6);
      expect(typed.transpose2D().at([2, 1]), 6);
    });

    test('supports slices, indexed mapping, stacking, and conversion', () {
      const codec = LogicValueCodec<int>(
        decode: _decodeLogicValue,
        encode: _encodeLogicValue,
      );
      final values = LogicValueArrayOf<int>(
        [2, 2],
        8,
        [1, 2, 3, 4],
        codec: codec,
      );

      expect(values.majorSlices.map((slice) => slice.flatValues), [
        [1, 2],
        [3, 4],
      ]);
      expect(
        values.indexedMap((indices, value) => value + indices[1]).flatValues,
        [1, 3, 3, 5],
      );
      expect(
        LogicValueArrayOf<int>.stack(values.majorSlices).flatValues,
        values.flatValues,
      );
      expect(values.logicValues.flatValues.map((value) => value.toInt()), [
        1,
        2,
        3,
        4,
      ]);
      expect(values.toLogicArray().dimensions, [2, 2]);
    });
  });
}
