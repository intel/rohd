// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_value_array_test.dart
// Tests for logic value arrays.
//
// 2026 September 16
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {
  group('LogicValueArray', () {
    test('constructs equivalent nested and flat row-major values', () {
      final leaves = [
        for (var value = 1; value <= 4; value++) LogicValue.ofInt(value, 8),
      ];
      final nested = LogicValueArray([
        [leaves[0], leaves[1]],
        [leaves[2], leaves[3]],
      ]);
      final flat = LogicValueArray.fromFlat(const [2, 2], leaves);
      final nestedInts = LogicValueArray.fromInts(const [
        [1, 2],
        [3, 4],
      ], elementWidth: 8);
      final flatInts = LogicValueArray.fromFlatInts(
        const [2, 2],
        const [1, 2, 3, 4],
        elementWidth: 8,
      );

      expect(nested.dimensions, [2, 2]);
      expect(nested.elementWidth, 8);
      expect(nested.arrayValues.length, 4);
      expect(nested.width, 32);
      // The deprecated LogicValue length retains its packed-bit meaning.
      // ignore: deprecated_member_use_from_same_package
      expect(nested.length, 32);
      expect(nested.arrayValues, leaves);
      expect(nested.packed, LogicValue.ofInt(0x04030201, 32));
      expect(flat, nested);
      expect(nestedInts, nested);
      expect(flatInts, nested);
    });

    test('indexes, slices, reshapes, transposes, and maps values', () {
      final values = LogicValueArray.fromInts(const [
        [1, 2, 3],
        [4, 5, 6],
      ], elementWidth: 8);

      expect(values.at([1, 1]).toInt(), 5);
      expect(values.indexedValues.last.$1, equals([1, 2]));
      expect(
        values.majorSlices.map((slice) =>
            slice.arrayValues.map((value) => value.toInt()).toList()),
        equals([
          [1, 2, 3],
          [4, 5, 6],
        ]),
      );
      expect(values.reshape([3, 2]).at([2, 1]).toInt(), 6);
      expect(
        values.transpose2D().arrayValues.map((value) => value.toInt()),
        [1, 4, 2, 5, 3, 6],
      );
      expect(
        values
            .indexedMap((indices, value) =>
                LogicValue.ofInt(value.toInt() + indices[0], 8))
            .arrayValues
            .map((value) => value.toInt()),
        equals([1, 2, 3, 5, 6, 7]),
      );
      expect(
        LogicValueArray.stack(values.majorSlices).dimensions,
        equals([2, 3]),
      );
    });

    test('supports empty, generated, mapped, and empty-stack contracts', () {
      var generatorCalls = 0;
      final generated = LogicValueArray.generate(
        const [2, 3],
        (indices) {
          generatorCalls++;
          return LogicValue.ofInt(indices[0] * 3 + indices[1] + 1, 8);
        },
      );
      final mapped = generated.map(
        (value) => LogicValue.ofInt(value.toInt() + 1, 8),
      );
      final empty = LogicValueArray.empty();
      var emptyMapCalls = 0;
      final mappedEmpty = empty.map((value) {
        emptyMapCalls++;
        return value;
      });
      final generatedEmpty = LogicValueArray.generate(
        const [2, 0],
        (indices) => throw StateError('Generator must not run for $indices.'),
        elementWidth: 8,
      );

      expect(generatorCalls, 6);
      expect(generated.elementWidth, 8);
      expect(generated.dimensions, [2, 3]);
      expect(
        generated.arrayValues.map((value) => value.toInt()),
        [1, 2, 3, 4, 5, 6],
      );
      expect(mapped, isA<LogicValueArray>());
      expect(
        mapped.arrayValues.map((value) => value.toInt()),
        [2, 3, 4, 5, 6, 7],
      );
      expect(empty.dimensions, [0]);
      expect(empty.elementWidth, 0);
      expect(empty.arrayValues.length, 0);
      expect(empty.width, 0);
      expect(empty.arrayValues, isEmpty);
      expect(empty.packed, LogicValue.empty);
      expect(emptyMapCalls, 0);
      expect(mappedEmpty.dimensions, [0]);
      expect(generatedEmpty.dimensions, [2, 0]);
      expect(generatedEmpty.elementWidth, 8);
      expect(generatedEmpty.arrayValues, isEmpty);
      expect(
        () => LogicValueArray.stack(const <LogicValueArray>[]),
        throwsArgumentError,
      );
      expect(
        () => TypedLogicValueArray<int>.stack(
            const <TypedLogicValueArray<int>>[]),
        throwsArgumentError,
      );
      expect(
        () => LogicValueArray.stack(
          LogicValueArray.fromFlat(const [0, 2], const [], elementWidth: 8)
              .majorSlices,
        ),
        throwsArgumentError,
      );
    });

    test('round-trips slices with an empty inner dimension', () {
      final values =
          LogicValueArray.fromFlat(const [2, 0], const [], elementWidth: 8);
      final slices = values.majorSlices.toList(growable: false);

      expect(slices, hasLength(2));
      expect(slices.map((slice) => slice.dimensions), [
        [0],
        [0],
      ]);
      expect(slices.map((slice) => slice.elementWidth), [8, 8]);
      expect(LogicValueArray.stack(slices).dimensions, [2, 0]);
    });

    test('matches packed semantics across storage and validity domains', () {
      final smallInvalid = LogicValueArray([
        LogicValue.ofString('1xz0'),
        LogicValue.ofString('z011'),
      ]);
      final wideInvalid = LogicValueArray([
        LogicValue.ofString('${'10' * 33}1xz0'),
        LogicValue.ofString('z0x1${'01' * 33}'),
      ]);
      final wideValid = LogicValueArray([
        LogicValue.ofBigInt(
          (BigInt.one << 69) | BigInt.from(0x1234),
          70,
        ),
        LogicValue.ofBigInt(
          (BigInt.one << 65) | BigInt.from(0x5678),
          70,
        ),
      ]);
      final testCases = [
        (
          name: 'small X/Z',
          shaped: smallInvalid,
          other: LogicValue.ofString('10z101x0'),
        ),
        (
          name: 'wide X/Z',
          shaped: wideInvalid,
          other: LogicValue.ofString('01xz' * 35),
        ),
        (
          name: 'wide valid',
          shaped: wideValid,
          other: LogicValue.ofBigInt(
            (BigInt.one << 138) | BigInt.from(0x9abc),
            140,
          ),
        ),
      ];
      final binaryOperations = <({
        String name,
        LogicValue Function(LogicValue left, LogicValue right) apply,
      })>[
        (name: 'and', apply: (left, right) => left & right),
        (name: 'or', apply: (left, right) => left | right),
        (name: 'xor', apply: (left, right) => left ^ right),
        (name: 'triState', apply: (left, right) => left.triState(right)),
        (name: 'add', apply: (left, right) => left + right),
        (name: 'subtract', apply: (left, right) => left - right),
        (name: 'multiply', apply: (left, right) => left * right),
      ];

      for (final testCase in testCases) {
        final shaped = testCase.shaped;
        final packed = shaped.packed;
        final other = testCase.other;
        final reshaped = shaped.reshape([1, shaped.arrayValues.length]);

        expect(shaped, packed, reason: testCase.name);
        expect(packed, shaped, reason: testCase.name);
        expect(shaped, reshaped, reason: testCase.name);
        expect(shaped.hashCode, packed.hashCode, reason: testCase.name);
        expect(shaped.hashCode, reshaped.hashCode, reason: testCase.name);
        expect({shaped, packed, reshaped}, hasLength(1));
        expect(LogicValue.ofIterable([shaped]), packed);
        expect(shaped.isValid, packed.isValid);
        expect(shaped.isFloating, packed.isFloating);
        expect(shaped.isZero, packed.isZero);
        expect(shaped[0], packed[0]);
        expect(shaped[-1], packed[-1]);
        expect(shaped.getRange(2, shaped.width - 2),
            packed.getRange(2, packed.width - 2));
        expect(shaped.slice(shaped.width - 3, 1),
            packed.slice(packed.width - 3, 1));
        expect(shaped.reversed, packed.reversed);
        expect(~shaped, ~packed);
        expect(shaped.and(), packed.and());
        expect(shaped.or(), packed.or());
        expect(shaped.xor(), packed.xor());
        expect(shaped << 3, packed << 3);
        expect(shaped >> 3, packed >> 3);
        expect(shaped >>> 3, packed >>> 3);
        if (shaped.isValid) {
          expect(shaped.toBigInt(), packed.toBigInt());
        }
        if (testCase.name.startsWith('wide')) {
          expect(shaped.width, greaterThan(64));
        }

        for (final operation in binaryOperations) {
          expect(
            operation.apply(shaped, other),
            operation.apply(packed, other),
            reason: '${testCase.name}: shaped ${operation.name} packed',
          );
          expect(
            operation.apply(other, shaped),
            operation.apply(other, packed),
            reason: '${testCase.name}: packed ${operation.name} shaped',
          );
        }
      }
    });

    test('rejects ragged, inconsistent, empty, and mismatched input', () {
      final one = LogicValue.ofInt(1, 8);
      expect(() => LogicValueArray(const []), throwsArgumentError);
      expect(
        () => LogicValueArray([
          [one],
          [one, one],
        ]),
        throwsArgumentError,
      );
      expect(
        () => LogicValueArray([
          one,
          [one],
        ]),
        throwsArgumentError,
      );
      expect(
        () => LogicValueArray([one, LogicValue.ofInt(2, 4)]),
        throwsArgumentError,
      );
      expect(
        () => LogicValueArray.fromFlat(const [2, 2], [one]),
        throwsArgumentError,
      );
      expect(
        LogicValueArray.fromFlat(
          const [2],
          [LogicValue.ofInt(1, 4), LogicValue.ofInt(2, 4)],
        ).elementWidth,
        4,
      );
      expect(
        LogicValueArray.fromFlat(
          const [2],
          [LogicValue.ofInt(1, 4), LogicValue.ofInt(2, 4)],
          elementWidth: 4,
        ).elementWidth,
        4,
      );
      expect(
        () => LogicValueArray.fromFlat(
          const [2],
          [LogicValue.ofInt(1, 4), LogicValue.ofInt(2, 3)],
        ),
        throwsArgumentError,
      );
      expect(
        () => LogicValueArray.fromFlat(
          const [2],
          [LogicValue.ofInt(1, 4), LogicValue.ofInt(2, 4)],
          elementWidth: 3,
        ),
        throwsArgumentError,
      );
      expect(
        () => LogicValueArray.fromInts(const [], elementWidth: 8),
        throwsArgumentError,
      );
      expect(
          () => LogicValueArray.fromFlat(const [], const [], elementWidth: 8),
          throwsArgumentError);
      expect(
        LogicValueArray.fromFlat(const [2, 0], const [], elementWidth: 8)
            .elementWidth,
        8,
      );
      expect(
        () => LogicValueArray.fromFlat(const [2, 0], const []),
        throwsArgumentError,
      );
    });

    test('rejects invalid value indices, shapes, widths, and stacks', () {
      final values = LogicValueArray.fromFlatInts(
        const [2, 2],
        const [1, 2, 3, 4],
        elementWidth: 8,
      );
      final oneDimensional = LogicValueArray.fromFlatInts(
        const [4],
        const [1, 2, 3, 4],
        elementWidth: 8,
      );
      final threeDimensional = LogicValueArray.fromFlatInts(
        const [1, 2, 2],
        const [1, 2, 3, 4],
        elementWidth: 8,
      );

      for (final indices in <List<int>>[
        [0],
        [-1, 0],
        [2, 0],
        [0, 2],
      ]) {
        expect(() => values.at(indices), throwsA(isA<RangeError>()));
      }
      expect(() => values.reshape([3]), throwsArgumentError);
      expect(() => values.reshape([-2, -2]), throwsArgumentError);
      expect(
        () => oneDimensional.majorSlices.toList(),
        throwsA(isA<StateError>()),
      );
      expect(
        oneDimensional.transpose2D,
        throwsA(isA<StateError>()),
      );
      expect(
        threeDimensional.transpose2D,
        throwsA(isA<StateError>()),
      );
      expect(
        () => LogicValueArray.fromFlat(const [-1], const [], elementWidth: 8),
        throwsArgumentError,
      );
      expect(
        () => LogicValueArray.fromFlat(const [1], const [], elementWidth: -1),
        throwsArgumentError,
      );
      expect(
        () => LogicValueArray.generate(
          const [1],
          (indices) => LogicValue.ofInt(indices.single, 4),
          elementWidth: 8,
        ),
        throwsArgumentError,
      );
      expect(
        () => LogicValueArray.stack([
          LogicValueArray.fromFlatInts(const [2], const [1, 2],
              elementWidth: 8),
          LogicValueArray.fromFlatInts(const [1, 2], const [3, 4],
              elementWidth: 8),
        ]),
        throwsArgumentError,
      );
      expect(
        () => LogicValueArray.stack([
          LogicValueArray.fromFlatInts(const [2], const [1, 2],
              elementWidth: 8),
          LogicValueArray.fromFlatInts(const [2], const [3, 4],
              elementWidth: 4),
        ]),
        throwsArgumentError,
      );
    });
  });
}
