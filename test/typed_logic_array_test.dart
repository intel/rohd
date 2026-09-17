// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// typed_logic_array_test.dart
// Tests for typed logic and logic value arrays.
//
// 2026 July 21
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

// Test fixtures intentionally use mutable literals to exercise array APIs.
// ignore_for_file: prefer_const_literals_to_create_immutables

import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

const _iverilogUnpackedArrayWorkaround = SystemVerilogSynthesizerConfiguration(
  iverilogWorkaroundForUnpackedArrayVariables: true,
);

class _SampleStructure extends LogicStructure {
  final Logic low;
  final Logic high;
  final String format;

  factory _SampleStructure({String? name, String format = 'sample'}) =>
      _SampleStructure._(
        Logic(name: 'low'),
        Logic(name: 'high', width: 2),
        format,
        name: name ?? 'sample',
      );

  _SampleStructure._(this.low, this.high, this.format, {required String name})
      : super([low, high], name: name);

  @override
  _SampleStructure clone({String? name}) =>
      _SampleStructure(name: name ?? this.name, format: format);
}

@immutable
class _SampleValue {
  final LogicValue value;

  _SampleValue(this.value) {
    if (value.width != 3) {
      throw ArgumentError.value(value, 'value', 'Must have width 3.');
    }
  }

  LogicValue get low => value[0];

  LogicValue get high => value.getRange(1, 3);

  @override
  bool operator ==(Object other) =>
      other is _SampleValue && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

_SampleValue _decodeSampleValue(LogicValue value) => _SampleValue(value);

LogicValue _encodeSampleValue(_SampleValue value) => value.value;

const _sampleValueCodec = LogicValueCodec<_SampleValue>(
  decode: _decodeSampleValue,
  encode: _encodeSampleValue,
);

class _NetSampleStructure extends LogicStructure {
  final LogicNet low;
  final LogicNet high;

  factory _NetSampleStructure({String? name}) => _NetSampleStructure._(
        LogicNet(name: 'low'),
        LogicNet(name: 'high', width: 2),
        name: name ?? 'netSample',
      );

  _NetSampleStructure._(this.low, this.high, {required String name})
      : super([low, high], name: name);

  @override
  _NetSampleStructure clone({String? name}) =>
      _NetSampleStructure(name: name ?? this.name);
}

class _PartiallyNetSampleStructure extends LogicStructure {
  factory _PartiallyNetSampleStructure({String? name}) =>
      _PartiallyNetSampleStructure._(
        Logic(name: 'low'),
        LogicNet(name: 'high', width: 2),
        name: name ?? 'partiallyNetSample',
      );

  _PartiallyNetSampleStructure._(
    Logic low,
    LogicNet high, {
    required String name,
  }) : super([low, high], name: name);

  @override
  _PartiallyNetSampleStructure clone({String? name}) =>
      _PartiallyNetSampleStructure(name: name ?? this.name);
}

class _EmptyStructure extends LogicStructure {
  _EmptyStructure({String? name})
      : super(const <Logic>[], name: name ?? 'empty');

  @override
  _EmptyStructure clone({String? name}) =>
      _EmptyStructure(name: name ?? this.name);
}

class _SampleArray extends TypedLogicArray<_SampleStructure, _SampleValue> {
  final String schema;
  final List<String>? _constructionDimensionNames;

  // ignore: use_super_parameters - fixes the element builder for this subtype.
  _SampleArray(
    List<int> dimensions, {
    required this.schema,
    List<String>? dimensionNames,
    String? name,
    Naming? naming,
    int numUnpackedDimensions = 0,
  })  : _constructionDimensionNames = dimensionNames == null
            ? null
            : List<String>.unmodifiable(dimensionNames),
        super(
          dimensions,
          _SampleStructure.new,
          valueCodec: _sampleValueCodec,
          dimensionNames: dimensionNames,
          name: name,
          naming: naming,
          numUnpackedDimensions: numUnpackedDimensions,
        );

  @override
  _SampleArray createClone({
    String? name,
    Naming? naming,
    int? numUnpackedDimensions,
  }) =>
      _SampleArray(
        dimensions,
        schema: schema,
        dimensionNames: _constructionDimensionNames,
        name: name ?? this.name,
        naming: naming,
        numUnpackedDimensions:
            numUnpackedDimensions ?? this.numUnpackedDimensions,
      );

  @override
  _SampleArray clone({String? name}) => super.clone(name: name) as _SampleArray;
}

class _TypedArrayPortModule extends Module {
  TypedLogicArray<_SampleStructure, _SampleValue> get valuesOut =>
      output('valuesOut') as TypedLogicArray<_SampleStructure, _SampleValue>;

  _TypedArrayPortModule(
      TypedLogicArray<_SampleStructure, _SampleValue> valuesIn) {
    valuesIn = addTypedInput('valuesIn', valuesIn);
    final valuesOut = addTypedOutput('valuesOut', valuesIn.clone);
    for (final (index, source) in valuesIn.arrayElements.indexed) {
      final destination = valuesOut.arrayElements[index];
      destination.low <= source.low;
      destination.high <= ~source.high;
    }
  }
}

class _TypedNetArrayPortModule extends Module {
  late final TypedLogicArray<_NetSampleStructure, _SampleValue> values;

  _TypedNetArrayPortModule(
      TypedLogicArray<_NetSampleStructure, _SampleValue> source) {
    values = addTypedInOut('values', source);
  }
}

class _TypedArrayInterface extends Interface<_TypedArrayDirection> {
  _TypedArrayInterface() {
    setPorts([
      _SampleArray(
        [2],
        schema: 'interface',
        name: 'values',
      ),
    ], [
      _TypedArrayDirection.data
    ]);
  }

  @override
  _TypedArrayInterface clone() => _TypedArrayInterface();
}

enum _TypedArrayDirection { data }

class _TypedArrayInterfaceModule extends Module {
  _TypedArrayInterfaceModule(_TypedArrayInterface values) {
    _TypedArrayInterface().connectIO(
      this,
      values,
      inputTags: [_TypedArrayDirection.data],
    );
  }
}

class _TypedArrayHierarchy extends Module {
  TypedLogicArray<_SampleStructure, _SampleValue> get valuesOut =>
      output('valuesOut') as TypedLogicArray<_SampleStructure, _SampleValue>;

  _TypedArrayHierarchy(TypedLogicArray<_SampleStructure, _SampleValue> source) {
    final valuesIn = addTypedInput('valuesIn', source);
    final child = _TypedArrayPortModule(valuesIn);
    addTypedOutput('valuesOut', valuesIn.clone).gets(child.valuesOut);
  }
}

class _NestedArrayStructure extends LogicStructure {
  final Logic before;
  final LogicArray lanes;
  final TypedLogicArray<_SampleStructure, LogicValue> samples;
  final Logic after;

  factory _NestedArrayStructure({
    String? name,
    int numUnpackedDimensions = 0,
  }) =>
      _NestedArrayStructure._(
        Logic(name: 'before', width: 2),
        LogicArray(
          [2],
          3,
          name: 'lanes',
          numUnpackedDimensions: numUnpackedDimensions,
        ),
        TypedLogicArray<_SampleStructure, LogicValue>(
          [2],
          _SampleStructure.new,
          name: 'samples',
          numUnpackedDimensions: numUnpackedDimensions,
        ),
        Logic(name: 'after'),
        name: name ?? 'nested',
      );

  _NestedArrayStructure._(
    this.before,
    this.lanes,
    this.samples,
    this.after, {
    required String name,
  }) : super([before, lanes, samples, after], name: name);

  @override
  _NestedArrayStructure clone({String? name}) => _NestedArrayStructure(
        name: name ?? this.name,
        numUnpackedDimensions: lanes.numUnpackedDimensions,
      );
}

class _NineBitNestedStructure extends LogicStructure {
  final Logic prefix;
  final LogicArray payload;
  final Logic suffix;

  factory _NineBitNestedStructure({String? name}) => _NineBitNestedStructure._(
        Logic(name: 'prefix', width: 2),
        LogicArray([2], 3, name: 'payload'),
        Logic(name: 'suffix'),
        name: name ?? 'nineBitNested',
      );

  _NineBitNestedStructure._(
    this.prefix,
    this.payload,
    this.suffix, {
    required String name,
  }) : super([prefix, payload, suffix], name: name);

  @override
  _NineBitNestedStructure clone({String? name}) =>
      _NineBitNestedStructure(name: name ?? this.name);
}

class _MatrixCell extends LogicStructure {
  final Logic low;
  final Logic high;

  factory _MatrixCell({String? name}) => _MatrixCell._(
        Logic(name: 'low'),
        Logic(name: 'high', width: 2),
        name: name ?? 'matrixCell',
      );

  _MatrixCell._(this.low, this.high, {required String name})
      : super([low, high], name: name);

  @override
  _MatrixCell clone({String? name}) => _MatrixCell(name: name ?? this.name);
}

class _ArrayValuedElementStructure extends LogicStructure {
  final Logic prefix;
  final TypedLogicArray<TypedLogicArray<_MatrixCell, LogicValue>, LogicValue>
      matrix;
  final Logic suffix;
  final List<int> matrixDimensions;
  final int matrixUnpackedDimensions;

  factory _ArrayValuedElementStructure({
    List<int> matrixDimensions = const [2],
    int matrixUnpackedDimensions = 0,
    String? name,
  }) =>
      _ArrayValuedElementStructure._(
        Logic(name: 'prefix', width: 2),
        TypedLogicArray<TypedLogicArray<_MatrixCell, LogicValue>, LogicValue>(
          matrixDimensions,
          ({name}) => TypedLogicArray<_MatrixCell, LogicValue>(
            [3],
            _MatrixCell.new,
            name: name,
          ),
          name: 'matrix',
          numUnpackedDimensions: matrixUnpackedDimensions,
        ),
        Logic(name: 'suffix'),
        matrixDimensions: List<int>.unmodifiable(matrixDimensions),
        matrixUnpackedDimensions: matrixUnpackedDimensions,
        name: name ?? 'arrayValuedElement',
      );

  _ArrayValuedElementStructure._(
    this.prefix,
    this.matrix,
    this.suffix, {
    required this.matrixDimensions,
    required this.matrixUnpackedDimensions,
    required String name,
  }) : super([prefix, matrix, suffix], name: name);

  @override
  _ArrayValuedElementStructure clone({String? name}) =>
      _ArrayValuedElementStructure(
        matrixDimensions: matrixDimensions,
        matrixUnpackedDimensions: matrixUnpackedDimensions,
        name: name ?? this.name,
      );
}

class _NestedPackedOffsetModule extends Module {
  _NestedPackedOffsetModule(
      TypedLogicArray<TypedLogicArray<_NineBitNestedStructure, LogicValue>,
              LogicValue>
          source) {
    final values = addTypedInput('values', source);
    addOutput('selected', width: 2) <= values.at([1]).at([2]).prefix;
  }
}

class _NestedArrayBoundaryModule extends Module {
  _NestedArrayBoundaryModule(
      TypedLogicArray<TypedLogicArray<_NestedArrayStructure, LogicValue>,
              LogicValue>
          source) {
    final input = addTypedInput('valuesIn', source);
    final child = _NestedArrayBoundaryChild(input);
    addTypedOutput('valuesOut', input.clone).gets(child.valuesOut);
  }
}

class _NestedArrayBoundaryChild extends Module {
  late final TypedLogicArray<TypedLogicArray<_NestedArrayStructure, LogicValue>,
      LogicValue> valuesOut;

  _NestedArrayBoundaryChild(
      TypedLogicArray<TypedLogicArray<_NestedArrayStructure, LogicValue>,
              LogicValue>
          input) {
    input = addTypedInput('valuesIn', input);
    valuesOut = addTypedOutput('valuesOut', input.clone);
    for (var outer = 0; outer < 2; outer++) {
      for (var inner = 0; inner < 3; inner++) {
        final sourceElement = input.at([1 - outer]).at([2 - inner]);
        final destination = valuesOut.at([outer]).at([inner]);
        destination.before <= sourceElement.before;
        destination.after <= ~sourceElement.after;
        for (var lane = 0; lane < 2; lane++) {
          destination.lanes.at([lane]) <= sourceElement.lanes.at([1 - lane]);
          final sourceSample = sourceElement.samples.at([1 - lane]);
          final destinationSample = destination.samples.at([lane]);
          destinationSample.low <= sourceSample.low;
          destinationSample.high <= ~sourceSample.high;
        }
      }
    }
  }
}

class _ArrayValuedElementFieldModule extends Module {
  _ArrayValuedElementFieldModule(
    TypedLogicArray<_ArrayValuedElementStructure, LogicValue> source, {
    List<int> matrixIndices = const [1],
  }) {
    final input = addTypedInput('values', source);
    final child = _ArrayValuedElementFieldChild(input, matrixIndices);
    addOutput('selected', width: 2).gets(child.selected);
  }
}

class _ArrayValuedElementFieldChild extends Module {
  late final Logic selected;

  _ArrayValuedElementFieldChild(
    TypedLogicArray<_ArrayValuedElementStructure, LogicValue> source,
    List<int> matrixIndices,
  ) {
    final values = addTypedInput('values', source);
    selected = addOutput('selected', width: 2);
    selected <= values.at([1]).matrix.at(matrixIndices).at([2]).high;
  }
}

class _ArrayValuedElementPayloadModule extends Module {
  _ArrayValuedElementPayloadModule(
      TypedLogicArray<_ArrayValuedElementStructure, LogicValue> source) {
    final values = addTypedInput('values', source);
    addOutput('selected', width: 9) <= values.at([1]).matrix.at([1]);
  }
}

class _MixedNestedArrayModule extends Module {
  _MixedNestedArrayModule(
      TypedLogicArray<TypedLogicArray<Logic, LogicValue>, LogicValue> source) {
    final input = addTypedInput('valuesIn', source);
    final child = _MixedNestedArrayChild(input);
    addTypedOutput('valuesOut', input.clone).gets(child.valuesOut);
  }
}

class _MixedNestedArrayChild extends Module {
  late final TypedLogicArray<TypedLogicArray<Logic, LogicValue>, LogicValue>
      valuesOut;

  _MixedNestedArrayChild(
      TypedLogicArray<TypedLogicArray<Logic, LogicValue>, LogicValue> input) {
    input = addTypedInput('valuesIn', input);
    valuesOut = addTypedOutput('valuesOut', input.clone);
    for (final (outerIndex, sourceElement) in input.indexedElements) {
      final destination = valuesOut.at(outerIndex);
      for (var row = 0; row < 4; row++) {
        for (var column = 0; column < 5; column++) {
          destination.at([row, column]) <=
              sourceElement.at([3 - row, 4 - column]);
        }
      }
    }
  }
}

LogicValue _nestedPacked(
  int before,
  int lane0,
  int lane1,
  int sample0,
  int sample1,
  int after,
) =>
    LogicValue.ofInt(
      before |
          (lane0 << 2) |
          (lane1 << 5) |
          (sample0 << 8) |
          (sample1 << 11) |
          (after << 14),
      15,
    );

LogicValue _nineBitNestedPacked(
        int prefix, int payload0, int payload1, int suffix) =>
    LogicValue.ofInt(
      prefix | (payload0 << 2) | (payload1 << 5) | (suffix << 8),
      9,
    );

LogicValue _arrayValuedElementPacked(
  List<int> matrixDimensions,
  List<int> matrixIndices,
) {
  var matrixElementIndex = 0;
  for (var index = 0; index < matrixDimensions.length; index++) {
    matrixElementIndex =
        matrixElementIndex * matrixDimensions[index] + matrixIndices[index];
  }
  final matrixWidth = matrixDimensions.fold(1, (width, size) => width * size);
  return LogicValue.ofInt(
    2 << (2 + matrixElementIndex * 9 + 7),
    2 + matrixWidth * 9 + 1,
  );
}

class _TypedInputModule<T extends Logic> extends Module {
  late final T values;

  _TypedInputModule(T source) {
    values = addTypedInput('values', source);
  }
}

void main() {
  group('TypedLogicArray', () {
    test('requires at least one dimension', () {
      expect(
        () => TypedLogicArray<Logic, LogicValue>(
          [],
          ({name}) => Logic(name: name),
        ),
        throwsA(
          predicate<LogicConstructionException>(
            (exception) => exception.reason.contains('at least 1 dimension'),
          ),
        ),
      );
    });

    test('keeps structured leaves at the array boundary', () {
      final values = TypedLogicArray<_SampleStructure, LogicValue>(
        [2, 3],
        _SampleStructure.new,
        dimensionNames: const ['row_', 'column_'],
      );

      expect(values, isA<TypedLogicArray<_SampleStructure, LogicValue>>());
      expect(values.dimensions, equals([2, 3]));
      expect(values.elementWidth, 3);
      expect(values.arrayElements, hasLength(6));
      expect(values.arrayElements, everyElement(isA<_SampleStructure>()));
      expect(values.leafElements, hasLength(12));
      expect(values.at([1, 2]), same(values.arrayElements[5]));
      expect(values.indexedElements.last.$1, equals([1, 2]));
    });

    test('preserves typed metadata through hardware cloning', () {
      final values = _SampleArray(
        [2, 2],
        schema: 'sample-v2',
        dimensionNames: const ['row_', 'column_'],
        numUnpackedDimensions: 1,
      );
      final assigned = TypedLogicValueArray<_SampleValue>.fromFlat(
        [2, 2],
        3,
        [
          _SampleValue(LogicValue.ofString('1xz')),
          _SampleValue(LogicValue.ofString('z01')),
          _SampleValue(LogicValue.ofString('010')),
          _SampleValue(LogicValue.ofString('111')),
        ],
        codec: _sampleValueCodec,
      );

      values.put(assigned);

      expect(values.value, isA<TypedLogicValueArray<_SampleValue>>());
      expect(values.value.arrayValues, assigned.arrayValues);
      expect(values.value.packed, assigned.packed);
      expect(values.value.at([0, 0]).value, LogicValue.ofString('1xz'));
      expect(values.value.at([0, 1]).high, LogicValue.ofString('z0'));
      expect(identical(values.value.codec, _sampleValueCodec), isTrue);

      final transformed = [
        values.clone(),
      ];
      for (final result in transformed) {
        expect(result, isA<TypedLogicArray<_SampleStructure, _SampleValue>>());
        expect(identical(result.valueCodec, _sampleValueCodec), isTrue);
        expect(result.numUnpackedDimensions, 1);
        expect(result.value, isA<TypedLogicValueArray<_SampleValue>>());
      }
    });

    test('preserves typed values through inherited inject and previousValue',
        () async {
      addTearDown(Simulator.reset);
      final values = _SampleArray([2], schema: 'sample-v2')..put(0);
      final injected = TypedLogicValueArray<_SampleValue>.fromFlat(
        [2],
        3,
        [
          _SampleValue(LogicValue.ofString('1xz')),
          _SampleValue(LogicValue.ofString('z01')),
        ],
        codec: _sampleValueCodec,
      );
      final changes = <LogicValueChanged>[];
      final subscription = values.changed.listen(changes.add);
      addTearDown(subscription.cancel);

      values.inject(injected);
      expect(values.value.packed, LogicValue.ofInt(0, 6));

      await Simulator.run();

      expect(values.value, isA<TypedLogicValueArray<_SampleValue>>());
      expect(values.value.arrayValues, injected.arrayValues);
      expect(values.previousValue, isA<TypedLogicValueArray<_SampleValue>>());
      expect(values.previousValue!.packed, LogicValue.ofInt(0, 6));
      expect(identical(values.previousValue!.codec, _sampleValueCodec), isTrue);
      expect(changes, hasLength(1));
      expect(changes.single.previousValue, LogicValue.ofInt(0, 6));
      expect(changes.single.newValue, injected.packed);
    });

    test('requires semantic codecs and compatible element formats', () {
      expect(
        () => TypedLogicArray<_SampleStructure, _SampleValue>(
          [1],
          _SampleStructure.new,
        ),
        throwsArgumentError,
      );

      var buildIndex = 0;
      expect(
        () => TypedLogicArray<_SampleStructure, _SampleValue>(
          [2],
          ({name}) => _SampleStructure(
            name: name,
            format: buildIndex++ == 0 ? 'binary16' : 'binary32',
          ),
          valueCodec: _sampleValueCodec,
          elementCompatibility: (prototype, element) =>
              prototype.format == element.format,
        ),
        throwsA(isA<LogicConstructionException>()),
      );

      final wrongWidthCodec = LogicValueCodec<_SampleValue>(
        decode: _decodeSampleValue,
        encode: (value) => value.value.zeroExtend(4),
      );
      expect(
        () => TypedLogicArray<_SampleStructure, _SampleValue>(
          [1],
          _SampleStructure.new,
          valueCodec: wrongWidthCodec,
        ),
        throwsA(isA<LogicConstructionException>()),
      );
    });

    test('matches ordinary LogicArray contracts for Logic leaves', () {
      final arrays = <TypedLogicArray<Logic, LogicValue>>[
        LogicArray(
          [2, 3],
          4,
          name: 'ordinary',
          numUnpackedDimensions: 1,
        ),
        TypedLogicArray<Logic, LogicValue>(
          [2, 3],
          ({name}) => Logic(name: name, width: 4),
          name: 'typed',
          numUnpackedDimensions: 1,
        ),
      ];
      final packed = LogicValueArray.fromFlatInts(
        [6],
        [1, 2, 3, 4, 5, 6],
        elementWidth: 4,
      );

      for (final array in arrays) {
        array.put(packed);

        expect(array.dimensions, [2, 3]);
        expect(array.elementWidth, 4);
        expect(array.width, 24);
        expect(array.numUnpackedDimensions, 1);
        expect(
          array.indexedElements.map((entry) => entry.$1),
          [
            [0, 0],
            [0, 1],
            [0, 2],
            [1, 0],
            [1, 1],
            [1, 2],
          ],
        );
        expect(array.at([1, 2]), same(array.arrayElements[5]));
        expect(
          array.value.arrayValues.map((value) => value.toInt()),
          [1, 2, 3, 4, 5, 6],
        );

        final slices = array.majorSlices.toList(growable: false);
        expect(slices, hasLength(2));
        expect(slices.first, same(array.elements.first));
        expect(slices.last.dimensions, [3]);
        expect(slices.last.elementWidth, 4);
        expect(slices.last.numUnpackedDimensions, 0);
        expect(slices.last.at([2]), same(array.at([1, 2])));

        final clone = array.clone();
        expect(clone is LogicArray, array is LogicArray);
        expect(clone.dimensions, array.dimensions);
        expect(clone.elementWidth, array.elementWidth);
        expect(clone.numUnpackedDimensions, array.numUnpackedDimensions);
        expect(clone.isNet, array.isNet);
      }
    });

    test('inherits packed LogicArray operations for structured leaves', () {
      final source = TypedLogicArray<_SampleStructure, LogicValue>(
        [2, 2],
        _SampleStructure.new,
        dimensionNames: const ['row_', 'column_'],
        numUnpackedDimensions: 1,
      )..put(LogicValue.ofInt(0xabc, 12));
      final differentlyShaped = TypedLogicArray<_SampleStructure, LogicValue>(
        [4],
        _SampleStructure.new,
      )..gets(source);
      final slice = source.slice(8, 2);
      final update = Const(0x15, width: 5);
      final updated = source.withSet(2, update);

      expect(differentlyShaped.value.packed, source.value.packed);
      expect(slice.value, source.value.packed.slice(8, 2));
      expect(updated, isA<TypedLogicArray<_SampleStructure, LogicValue>>());
      final typedUpdated =
          updated as TypedLogicArray<_SampleStructure, LogicValue>;
      expect(typedUpdated.dimensions, [2, 2]);
      expect(typedUpdated.elementWidth, 3);
      expect(typedUpdated.numUnpackedDimensions, 1);
      expect(
        typedUpdated.value.packed,
        source.value.packed.withSet(2, update.value),
      );
    });

    test('majorSlices returns existing typed child arrays', () {
      final values = TypedLogicArray<_SampleStructure, LogicValue>(
        [2, 3, 2],
        _SampleStructure.new,
        dimensionNames: const ['row_', 'column_', 'lane_'],
        numUnpackedDimensions: 2,
      );
      final slices = values.majorSlices.toList(growable: false);

      expect(slices, hasLength(2));
      expect(slices.first, same(values.elements.first));
      expect(slices.last, same(values.elements.last));
      for (final slice in slices) {
        expect(slice, isA<TypedLogicArray<_SampleStructure, LogicValue>>());
        expect(slice.dimensions, [3, 2]);
        expect(slice.elementWidth, 3);
        expect(slice.numUnpackedDimensions, 1);
        expect(
          slice.arrayElements,
          everyElement(isA<_SampleStructure>()),
        );
      }
      expect(slices.last.at([2, 1]), same(values.at([1, 2, 1])));
      expect(
        () => TypedLogicArray<_SampleStructure, LogicValue>(
          [2],
          _SampleStructure.new,
        ).majorSlices.toList(),
        throwsA(isA<StateError>()),
      );
    });

    test('provides typed indexing and cloning', () {
      final values = TypedLogicArray<Logic, LogicValue>(
        [2, 2],
        ({name}) => Logic(name: name, width: 8),
      );
      final clone = values.clone(name: 'clone');

      expect(values.at([1, 0]), same(values.arrayElements[2]));
      expect(clone, isA<TypedLogicArray<Logic, LogicValue>>());
      expect(clone.name, 'clone');
      expect(clone.arrayElements, hasLength(4));
      values <= LogicArray([4], 8);
      expect(
        () => values <= LogicArray([2, 2], 4),
        throwsA(isA<SignalWidthMismatchException>()),
      );
    });

    test('ordinary assignment drives structured leaves in row-major order', () {
      final values = TypedLogicArray<_SampleStructure, LogicValue>(
        [2, 2],
        _SampleStructure.new,
      );
      final packed = LogicArray([2, 2], 3)
        ..put(LogicValueArray.fromFlatInts(
          [4],
          [1, 2, 3, 4],
          elementWidth: 3,
        ));

      values <= packed;

      expect(values.value.packed, packed.value.packed);
      expect(
        values.value.arrayValues.map((value) => value.toInt()),
        [1, 2, 3, 4],
      );
      expect(
        values.leafElements.every((leaf) => leaf.srcConnections.isNotEmpty),
        isTrue,
      );
    });

    test('derives the net kind for empty multidimensional typed arrays', () {
      var logicBuilds = 0;
      var netBuilds = 0;
      final logicValues = TypedLogicArray<Logic, LogicValue>(
        [2, 0],
        ({name}) {
          logicBuilds++;
          return Logic(name: name, width: 8);
        },
      );
      final netValues = TypedLogicArray<LogicNet, LogicValue>(
        [2, 3, 0],
        ({name}) {
          netBuilds++;
          return LogicNet(name: name, width: 8);
        },
      );

      expect(logicBuilds, 1);
      expect(netBuilds, 1);
      expect(logicValues.isNet, isFalse);
      expect(logicValues.elements.every((element) => !element.isNet), isTrue);
      expect(netValues.isNet, isTrue);
      expect(netValues.elements.every((element) => element.isNet), isTrue);
      expect(
        _TypedInputModule(logicValues).values,
        isA<TypedLogicArray<Logic, LogicValue>>(),
      );
    });

    test('requires a uniform recursive net composition', () {
      var buildIndex = 0;
      expect(
        () => TypedLogicArray<Logic, LogicValue>(
          [2],
          ({name}) => buildIndex++ == 0
              ? Logic(name: name, width: 3)
              : LogicNet(name: name, width: 3),
        ),
        throwsA(isA<LogicConstructionException>()),
      );
      expect(
        () => TypedLogicArray<_PartiallyNetSampleStructure, LogicValue>(
          [2],
          _PartiallyNetSampleStructure.new,
        ),
        throwsA(isA<LogicConstructionException>()),
      );
      expect(
        () => TypedLogicArray<_PartiallyNetSampleStructure, LogicValue>(
          [0],
          _PartiallyNetSampleStructure.new,
        ),
        throwsA(isA<LogicConstructionException>()),
      );
      var structureBuildIndex = 0;
      expect(
        () => TypedLogicArray<LogicStructure, LogicValue>(
          [2],
          ({name}) => structureBuildIndex++ == 0
              ? _SampleStructure(name: name)
              : _NetSampleStructure(name: name),
        ),
        throwsA(isA<LogicConstructionException>()),
      );

      final logicValues = TypedLogicArray<_SampleStructure, LogicValue>(
        [2],
        _SampleStructure.new,
      );
      final emptyStructureValues = TypedLogicArray<_EmptyStructure, LogicValue>(
        [0],
        _EmptyStructure.new,
      );
      final netValues = TypedLogicArray<_NetSampleStructure, LogicValue>(
        [2, 2],
        _NetSampleStructure.new,
      );
      expect(logicValues.isNet, isFalse);
      expect(emptyStructureValues.isNet, isFalse);
      expect(netValues.isNet, isTrue);
      expect(netValues.arrayElements, everyElement(isA<_NetSampleStructure>()));
      expect(
        netValues.arrayElements
            .expand((element) => element.leafElements)
            .every((element) => element.isNet),
        isTrue,
      );
    });

    test('validates dimensions, names, and leaf widths', () {
      expect(
        () => TypedLogicArray<Logic, LogicValue>(const [], Logic.new),
        throwsA(isA<LogicConstructionException>()),
      );
      expect(
        () => TypedLogicArray<Logic, LogicValue>(
          [2],
          Logic.new,
          dimensionNames: const [],
        ),
        throwsA(isA<LogicConstructionException>()),
      );
      expect(
        () => TypedLogicArray<Logic, LogicValue>(
          [2, 2],
          Logic.new,
          dimensionNames: const ['row.', 'column_'],
        ),
        throwsA(isA<LogicConstructionException>()),
      );
      expect(
        () => TypedLogicArray<Logic, LogicValue>(
          [2, 2],
          Logic.new,
          dimensionNames: const ['row_', 'row_'],
        ),
        throwsA(isA<LogicConstructionException>()),
      );
      expect(
        () => TypedLogicArray<Const, LogicValue>(
          [2],
          ({name}) => Const(0, width: 1),
        ),
        throwsA(isA<LogicConstructionException>()),
      );

      var width = 1;
      expect(
        () => TypedLogicArray<Logic, LogicValue>(
          [2],
          ({name}) => Logic(name: name, width: width++),
        ),
        throwsA(isA<LogicConstructionException>()),
      );

      for (final create in <Logic Function()>[
        () => LogicArray([-1], 1),
        () => LogicArray([0], -1),
        () => LogicArray([1], 1, numUnpackedDimensions: -1),
        () => TypedLogicArray<Logic, LogicValue>(
              [-1],
              ({name}) => Logic(name: name),
            ),
        () => TypedLogicArray<Logic, LogicValue>(
              [1],
              ({name}) => Logic(name: name),
              numUnpackedDimensions: -1,
            ),
        () => TypedLogicArray<Logic, LogicValue>(
              [1],
              ({name}) => Logic(name: name),
              numUnpackedDimensions: 2,
            ),
      ]) {
        expect(create, throwsA(isA<LogicConstructionException>()));
      }
    });

    test('rejects invalid indexing', () {
      final values = TypedLogicArray<Logic, LogicValue>(
        [2, 2],
        ({name}) => Logic(name: name, width: 2),
      );

      for (final indices in <List<int>>[
        [0],
        [-1, 0],
        [2, 0],
        [0, 2],
      ]) {
        expect(() => values.at(indices), throwsA(isA<RangeError>()));
      }
    });

    test('named applies every requested naming mode', () {
      final values = TypedLogicArray<Logic, LogicValue>(
        [2],
        Logic.new,
        name: 'values',
        naming: Naming.mergeable,
      );

      for (final naming in Naming.values) {
        final name = 'renamed_${naming.name}';
        final renamed = values.named(name, naming: naming);
        expect(renamed.name, name);
        expect(renamed.naming, naming);
      }
    });

    test('matches LogicArray clone naming policy for every naming mode', () {
      for (final originalNaming in Naming.values) {
        final typed = TypedLogicArray<Logic, LogicValue>(
          [2],
          Logic.new,
          name: 'typed_${originalNaming.name}',
          naming: originalNaming,
        );
        final ordinary = LogicArray(
          [2],
          1,
          name: 'ordinary_${originalNaming.name}',
          naming: originalNaming,
        );
        final typedClone = typed.clone();
        final ordinaryClone = ordinary.clone();
        final typedRenamed = typed.clone(name: 'typedClone');
        final ordinaryRenamed = ordinary.clone(name: 'ordinaryClone');

        expect(typedClone.naming, Naming.mergeable);
        expect(typedClone.naming, ordinaryClone.naming);
        expect(typedClone.name, typed.name);
        expect(typedRenamed.naming, Naming.renameable);
        expect(typedRenamed.naming, ordinaryRenamed.naming);
        expect(typedRenamed.name, 'typedClone');
      }
    });

    test('custom subclasses preserve runtime type and metadata when cloned',
        () {
      final values = _SampleArray(
        [2, 3],
        schema: 'sample-v2',
        dimensionNames: const ['row_', 'column_'],
        name: 'values',
        naming: Naming.reserved,
        numUnpackedDimensions: 1,
      );
      final clone = values.clone();
      final named = values.named('renamed', naming: Naming.reserved);

      for (final result in [clone, named]) {
        expect(result, isA<_SampleArray>());
        final specialized = result as _SampleArray;
        expect(specialized.schema, 'sample-v2');
        expect(specialized.dimensions, [2, 3]);
        expect(specialized.elementWidth, 3);
        expect(specialized.numUnpackedDimensions, 1);
        expect(specialized.isNet, isFalse);
        expect(identical(specialized.valueCodec, _sampleValueCodec), isTrue);
        expect(specialized.value, isA<TypedLogicValueArray<_SampleValue>>());
        expect(
          specialized.arrayElements,
          everyElement(isA<_SampleStructure>()),
        );
        expect(
          specialized.elements.map((element) => element.name),
          ['row_0', 'row_1'],
        );
        expect(
          specialized.arrayElements.map((element) => element.name),
          [
            'column_0',
            'column_1',
            'column_2',
            'column_0',
            'column_1',
            'column_2',
          ],
        );
      }
      expect(clone.name, 'values');
      expect(clone.naming, Naming.mergeable);
      expect(named.name, 'renamed');
      expect(named.naming, Naming.reserved);
    });

    test('assigns packed source forms independent of shape', () async {
      addTearDown(Simulator.reset);
      final codec = LogicValueCodec<int>(
        decode: (value) => value.toInt(),
        encode: (value) => LogicValue.ofInt(value, 3),
      );
      final values = TypedLogicArray<_SampleStructure, LogicValue>(
        [2, 2],
        _SampleStructure.new,
      );
      final sameShape = LogicValueArray.fromFlatInts(
        [2, 2],
        [0, 1, 2, 3],
        elementWidth: 3,
      );
      final differentShape = sameShape.reshape([4]);
      final typedValues = TypedLogicValueArray<int>.fromFlat(
        [1, 4],
        3,
        [7, 6, 5, 4],
        codec: codec,
      );
      final packedWithInvalid = LogicValue.ofString('10xz01z110x0');
      final assignmentCases = <({
        String name,
        Object value,
        LogicValue expected,
      })>[
        (
          name: 'integer',
          value: 0xa53,
          expected: LogicValue.ofInt(0xa53, 12),
        ),
        (
          name: 'ordinary LogicValue with X/Z',
          value: packedWithInvalid,
          expected: packedWithInvalid,
        ),
        (
          name: 'same-shape LogicValueArray',
          value: sameShape,
          expected: sameShape.packed,
        ),
        (
          name: 'different-shape LogicValueArray',
          value: differentShape,
          expected: differentShape.packed,
        ),
        (
          name: 'generic TypedLogicValueArray',
          value: typedValues,
          expected: typedValues.packed,
        ),
      ];

      for (final testCase in assignmentCases) {
        values.put(testCase.value);
        expect(
          values.value.packed,
          testCase.expected,
          reason: testCase.name,
        );
        expect(values.value.dimensions, [2, 2]);
        expect(values.value.elementWidth, 3);
      }

      final emptyValues =
          LogicValueArray.fromFlat([0, 3], const [], elementWidth: 3);
      final emptyTarget = TypedLogicArray<_SampleStructure, LogicValue>(
        [2, 0],
        _SampleStructure.new,
      )..put(emptyValues);
      expect(emptyTarget.value.dimensions, [2, 0]);
      expect(emptyTarget.value.elementWidth, 3);
      expect(emptyTarget.value.packed, LogicValue.empty);

      values.put(LogicValue.one, fill: true);
      expect(
        values.value.packed,
        LogicValue.filled(values.width, LogicValue.one),
      );
      expect(
        () => values.put(typedValues, fill: true),
        throwsA(isA<LogicValueConstructionException>()),
      );

      values
        ..put(0)
        ..inject(typedValues);
      expect(values.value.packed, LogicValue.ofInt(0, values.width));
      await Simulator.run();
      expect(
        TypedLogicValueArray<int>.fromLogicValueArray(
          values.value,
          codec: codec,
        ).arrayValues,
        [7, 6, 5, 4],
      );
    });

    test('value snapshots do not add hardware to structured arrays', () async {
      addTearDown(Simulator.reset);
      final initial = LogicValue.ofString('10xz01');
      final updated = LogicValue.ofString('z001x1');
      final values = TypedLogicArray<_SampleStructure, LogicValue>(
        [2],
        _SampleStructure.new,
      )..put(initial);
      final leaves = values.leafElements;

      Simulator.registerAction(10, () => values.put(updated));
      await Simulator.run();
      expect(
        leaves.where((leaf) =>
            leaf.srcConnections.isNotEmpty || leaf.dstConnections.isNotEmpty),
        isEmpty,
      );
      final first = values.value;
      final second = values.value;
      final previous = values.previousValue;

      expect(first, second);
      expect(first.dimensions, [2]);
      expect(first.elementWidth, 3);
      expect(first.packed, updated);
      expect(previous, isNotNull);
      expect(previous!.packed, initial);
      expect(
        leaves.where((leaf) =>
            leaf.srcConnections.isNotEmpty || leaf.dstConnections.isNotEmpty),
        isEmpty,
      );
    });

    test('tracks previous values and coalesces array changes per tick',
        () async {
      addTearDown(Simulator.reset);
      final values = TypedLogicArray<_SampleStructure, LogicValue>(
        [2],
        _SampleStructure.new,
      );
      final initial = LogicValue.ofString('01xz10');
      final updated = LogicValue.ofString('z10x01');
      final changes = <LogicValueChanged>[];

      values.put(initial);
      expect(values.previousValue, isNull);
      final subscription = values.changed.listen(changes.add);
      addTearDown(subscription.cancel);
      Simulator.registerAction(10, () => values.put(updated));

      await Simulator.run();

      expect(changes, hasLength(1));
      expect(changes.single.previousValue, initial);
      expect(changes.single.newValue, updated);
      expect(values.value.packed, updated);
      expect(values.previousValue, isA<TypedLogicValueArray<LogicValue>>());
      expect(values.previousValue!.dimensions, [2]);
      expect(values.previousValue!.elementWidth, 3);
      expect(values.previousValue!.packed, initial);
    });

    test('preserves specialized leaves in typed input and output ports', () {
      final source = _SampleArray([2, 3], schema: 'ports');
      final module = _TypedArrayPortModule(source);
      final valuesIn = module.input('valuesIn')
          as TypedLogicArray<_SampleStructure, _SampleValue>;

      expect(valuesIn, isA<TypedLogicArray<_SampleStructure, _SampleValue>>());
      expect(valuesIn.dimensions, [2, 3]);
      expect(valuesIn.at([1, 2]), isA<_SampleStructure>());
      expect(identical(valuesIn.valueCodec, _sampleValueCodec), isTrue);
      expect(valuesIn.value, isA<TypedLogicValueArray<_SampleValue>>());
      expect(module.valuesOut,
          isA<TypedLogicArray<_SampleStructure, _SampleValue>>());
      expect(identical(module.valuesOut.valueCodec, _sampleValueCodec), isTrue);
      expect(module.valuesOut.value, isA<TypedLogicValueArray<_SampleValue>>());
      expect(module.valuesOut.at([1, 2]).low.width, 1);
      expect(module.valuesOut.at([1, 2]).high.width, 2);
    });

    test('preserves and builds semantic net arrays through typed inout ports',
        () async {
      final source = TypedLogicArray<_NetSampleStructure, _SampleValue>(
        [2],
        _NetSampleStructure.new,
        valueCodec: _sampleValueCodec,
      );
      final module = _TypedNetArrayPortModule(source);

      expect(module.values,
          isA<TypedLogicArray<_NetSampleStructure, _SampleValue>>());
      expect(module.values.isNet, isTrue);
      expect(identical(module.values.valueCodec, _sampleValueCodec), isTrue);
      expect(module.values.value, isA<TypedLogicValueArray<_SampleValue>>());
      await module.build();
      SimCompare.checkIverilogVector(module, const [], buildOnly: true);
    });

    test('preserves typed arrays through interfaces and synthesis', () async {
      final source = _SampleArray(
        [2, 2],
        schema: 'hierarchy',
        name: 'valuesIn',
      );
      final module = _TypedArrayHierarchy(source);
      await module.build();

      final vectors = [
        Vector({'valuesIn': 0x129}, {'valuesOut': 0xc9f}),
        Vector({'valuesIn': 0xace}, {'valuesOut': 0x778}),
      ];
      await SimCompare.checkFunctionalVector(module, vectors);
      SimCompare.checkIverilogVector(module, vectors);

      final netlist = jsonDecode(NetlistSynthesizer().synthesizeToJson(module))
          as Map<String, dynamic>;
      final modules = (netlist['modules'] as Map<String, dynamic>)
          .values
          .cast<Map<String, dynamic>>();
      final typedModule = modules.firstWhere((moduleDefinition) {
        final cells = moduleDefinition['cells'] as Map<String, dynamic>;
        return cells.values.cast<Map<String, dynamic>>().any(
              (cell) => cell['type'] == r'$struct_unpack',
            );
      });
      final ports = typedModule['ports'] as Map<String, dynamic>;
      final inputPort = ports['valuesIn'] as Map<String, dynamic>;
      final outputPort = ports['valuesOut'] as Map<String, dynamic>;
      final inputType = inputPort['logic_type'] as Map<String, dynamic>;
      var elementType = inputType;
      while (elementType['elementType'] is Map<String, dynamic>) {
        elementType = elementType['elementType'] as Map<String, dynamic>;
      }
      final fields =
          (elementType['fields'] as List<dynamic>).cast<Map<String, dynamic>>();

      expect(inputType['arrayDims'], [2, 2]);
      expect(inputType['elementWidth'], 3);
      expect(fields, [
        {'name': 'low', 'width': 1},
        {'name': 'high', 'width': 2},
      ]);
      expect(inputPort['bits'], hasLength(12));
      expect(outputPort['bits'], hasLength(12));

      final cells = (typedModule['cells'] as Map<String, dynamic>)
          .values
          .cast<Map<String, dynamic>>();
      final structUnpacks =
          cells.where((cell) => cell['type'] == r'$struct_unpack').toList();
      final structPacks =
          cells.where((cell) => cell['type'] == r'$struct_pack').toList();
      final arraySlices =
          cells.where((cell) => cell['type'] == r'$slice').toList();
      final arrayConcats =
          cells.where((cell) => cell['type'] == r'$concat').toList();
      final inversions =
          cells.where((cell) => cell['type'] == r'$not').toList();
      final inputBits = (inputPort['bits'] as List<dynamic>).cast<Object>();
      final outputBits = (outputPort['bits'] as List<dynamic>).cast<Object>();
      List<Object> connection(Map<String, dynamic> cell, String port) =>
          ((cell['connections'] as Map<String, dynamic>)[port] as List<dynamic>)
              .cast<Object>();
      Map<String, dynamic> parameters(Map<String, dynamic> cell) =>
          cell['parameters'] as Map<String, dynamic>;
      String connectionKey(List<Object> bits) => bits.join(',');
      Iterable<List<Object>> inputConnections(Map<String, dynamic> cell) {
        final directions = cell['port_directions'] as Map<String, dynamic>;
        final connections = cell['connections'] as Map<String, dynamic>;
        return connections.entries
            .where((entry) => directions[entry.key] == 'input')
            .map((entry) => (entry.value as List<dynamic>).cast<Object>());
      }

      expect(structUnpacks, hasLength(4));
      expect(structPacks, hasLength(4));
      expect(arraySlices, hasLength(6));
      expect(arrayConcats, hasLength(3));
      expect(inversions, hasLength(4));

      final outerSlices = arraySlices
          .where((cell) => parameters(cell)['A_WIDTH'] == 12)
          .toList();
      final elementSlices = arraySlices
          .where((cell) => parameters(cell)['A_WIDTH'] == 6)
          .toList();
      expect(outerSlices, hasLength(2));
      expect(elementSlices, hasLength(4));
      expect(
        outerSlices.map((cell) => parameters(cell)['OFFSET']).toSet(),
        {0, 6},
      );
      for (final slice in outerSlices) {
        expect(connection(slice, 'A'), inputBits);
        expect(parameters(slice)['Y_WIDTH'], 6);
        expect(
          elementSlices
              .where(
                (elementSlice) =>
                    connectionKey(connection(elementSlice, 'A')) ==
                    connectionKey(connection(slice, 'Y')),
              )
              .map((elementSlice) => parameters(elementSlice)['OFFSET'])
              .toSet(),
          {0, 3},
        );
      }
      expect(
        structUnpacks
            .map((cell) => connectionKey(connection(cell, 'A')))
            .toSet(),
        elementSlices
            .map((cell) => connectionKey(connection(cell, 'Y')))
            .toSet(),
      );

      final elementConcats = arrayConcats
          .where((cell) => parameters(cell)['IN0_WIDTH'] == 3)
          .toList();
      final rootConcat = arrayConcats
          .singleWhere((cell) => parameters(cell)['IN0_WIDTH'] == 6);
      expect(elementConcats, hasLength(2));
      expect(
        structPacks.map((cell) => connectionKey(connection(cell, 'Y'))).toSet(),
        elementConcats.expand(inputConnections).map(connectionKey).toSet(),
      );
      expect(
        elementConcats.map((cell) => parameters(cell)['IN1_WIDTH']).toSet(),
        {3},
      );
      expect(connection(rootConcat, 'Y'), outputBits);
      expect(
        inputConnections(rootConcat).map(connectionKey).toSet(),
        elementConcats
            .map((cell) => connectionKey(connection(cell, 'Y')))
            .toSet(),
      );
      expect(
        structUnpacks
            .map((cell) => connectionKey(connection(cell, 'high')))
            .toSet(),
        inversions.map((cell) => connectionKey(connection(cell, 'A'))).toSet(),
      );
      expect(
        inversions.map((cell) => connectionKey(connection(cell, 'Y'))).toSet(),
        structPacks
            .map((cell) => connectionKey(connection(cell, 'high')))
            .toSet(),
      );
      expect(
        structUnpacks
            .map((cell) => connectionKey(connection(cell, 'low')))
            .toSet(),
        structPacks
            .map((cell) => connectionKey(connection(cell, 'low')))
            .toSet(),
      );
      for (final cell in [...structUnpacks, ...structPacks]) {
        final connections = cell['connections'] as Map<String, dynamic>;
        expect(connections['low'], hasLength(1));
        expect(connections['high'], hasLength(2));
      }

      final interfaceModule =
          _TypedArrayInterfaceModule(_TypedArrayInterface());
      await interfaceModule.build();
      expect(
        interfaceModule.input('values'),
        isA<TypedLogicArray<_SampleStructure, _SampleValue>>(),
      );
    });

    test('lowers array-valued elements to their parent packed offsets',
        () async {
      await Simulator.reset();
      final source = TypedLogicArray<
          TypedLogicArray<_NineBitNestedStructure, LogicValue>, LogicValue>(
        [2],
        ({name}) => TypedLogicArray<_NineBitNestedStructure, LogicValue>(
          [3],
          _NineBitNestedStructure.new,
          name: name,
        ),
      );
      final module = _NestedPackedOffsetModule(source);
      await module.build();

      final elements = [
        _nineBitNestedPacked(0, 1, 2, 0),
        _nineBitNestedPacked(1, 2, 3, 1),
        _nineBitNestedPacked(2, 3, 4, 0),
        _nineBitNestedPacked(3, 4, 5, 1),
        _nineBitNestedPacked(0, 5, 6, 0),
        _nineBitNestedPacked(2, 6, 7, 1),
      ];
      final vectors = [
        Vector(
          {'values': LogicValue.ofIterable(elements)},
          {'selected': elements.last.getRange(0, 2)},
        ),
      ];

      await SimCompare.checkFunctionalVector(module, vectors);
      final sv = module.generateSynth();
      expect(sv, contains('input logic [1:0][26:0] values'));
      expect(sv, contains('assign selected = values[1][19:18];'));
      expect(sv, isNot(contains('values[1][2][1:0]')));
      SimCompare.checkIverilogVector(module, vectors);
      SimCompare.checkVerilatorVector(module, vectors);
    }, tags: ['verilator']);

    test(
        'lowers separately declared array-valued structure fields by '
        'declaration rank', () async {
      await Simulator.reset();
      final source = TypedLogicArray<_ArrayValuedElementStructure, LogicValue>(
        [2],
        _ArrayValuedElementStructure.new,
      );
      final module = _ArrayValuedElementFieldModule(source);
      await module.build();
      final vectors = [
        Vector(
          {'values': LogicValue.ofInt(2 << 39, source.width)},
          {'selected': 2},
        ),
      ];

      await SimCompare.checkFunctionalVector(module, vectors);
      final sv = module.generateSynth();
      expect(sv, contains('logic [1:0][8:0] values_1__matrix;'));
      expect(sv, contains('values_1__matrix[1][8:7]'));
      expect(sv, isNot(contains('values_1__matrix[1][2][8:7]')));
      expect(
        sv,
        contains(
          'assign values_1__matrix_0[1][8:7] = '
          'values_1__matrix[1][8:7];',
        ),
      );
      SimCompare.checkIverilogVector(module, vectors);
      SimCompare.checkVerilatorVector(module, vectors);
    }, tags: ['verilator']);

    test('lowers unpacked separately declared array-valued structure fields',
        () async {
      await Simulator.reset();
      final source = TypedLogicArray<_ArrayValuedElementStructure, LogicValue>(
        [2],
        ({name}) => _ArrayValuedElementStructure(
          matrixUnpackedDimensions: 1,
          name: name,
        ),
      );
      final module = _ArrayValuedElementFieldModule(source);
      await module.build();
      final selectedElement = _arrayValuedElementPacked(const [2], const [1]);
      final vectors = [
        Vector(
          {
            'values': LogicValue.ofIterable([
              LogicValue.ofInt(0, selectedElement.width),
              selectedElement,
            ]),
          },
          {'selected': 2},
        ),
      ];

      await SimCompare.checkFunctionalVector(module, vectors);
      final sv = module.generateSynth();
      expect(sv, contains('logic [8:0] values_1__matrix [1:0];'));
      expect(sv, contains('values_1__matrix[1][8:7]'));
      expect(sv, isNot(contains('values_1__matrix[1][2][8:7]')));
      SimCompare.checkIverilogVector(module, vectors);
      SimCompare.checkVerilatorVector(module, vectors);
    }, tags: ['verilator']);

    test(
        'limits separately declared multidimensional array fields to '
        'their declaration rank', () async {
      await Simulator.reset();
      const matrixDimensions = [2, 2];
      const matrixIndices = [1, 0];
      final source = TypedLogicArray<_ArrayValuedElementStructure, LogicValue>(
        [2],
        ({name}) => _ArrayValuedElementStructure(
          matrixDimensions: matrixDimensions,
          name: name,
        ),
      );
      final module = _ArrayValuedElementFieldModule(
        source,
        matrixIndices: matrixIndices,
      );
      await module.build();
      final selectedElement =
          _arrayValuedElementPacked(matrixDimensions, matrixIndices);
      final vectors = [
        Vector(
          {
            'values': LogicValue.ofIterable([
              LogicValue.ofInt(0, selectedElement.width),
              selectedElement,
            ]),
          },
          {'selected': 2},
        ),
      ];

      await SimCompare.checkFunctionalVector(module, vectors);
      final sv = module.generateSynth();
      expect(sv, contains('logic [1:0][1:0][8:0] values_1__matrix;'));
      expect(sv, contains('values_1__matrix[1][0][8:7]'));
      expect(sv, isNot(contains('values_1__matrix[1][0][2][8:7]')));
      SimCompare.checkIverilogVector(module, vectors);
      SimCompare.checkVerilatorVector(module, vectors);
    }, tags: ['verilator']);

    test('reads a whole separately declared array-valued element', () async {
      await Simulator.reset();
      final source = TypedLogicArray<_ArrayValuedElementStructure, LogicValue>(
        [2],
        _ArrayValuedElementStructure.new,
      );
      final module = _ArrayValuedElementPayloadModule(source);
      await module.build();
      const payload = 0x15c;
      final vectors = [
        Vector(
          {'values': LogicValue.ofInt(payload << 32, source.width)},
          {'selected': payload},
        ),
      ];

      await SimCompare.checkFunctionalVector(module, vectors);
      final sv = module.generateSynth();
      expect(sv, contains('values_1__matrix[1][8:7]'));
      expect(sv, contains('values_1__matrix[1][0]'));
      expect(sv, isNot(contains('values_1__matrix[1][2][8:7]')));
      SimCompare.checkIverilogVector(module, vectors);
      SimCompare.checkVerilatorVector(module, vectors);
    }, tags: ['verilator']);

    test(
        'simulates packed and mixed nested arrays with array-valued '
        'structure fields', () async {
      await Simulator.reset();
      final source = TypedLogicArray<
          TypedLogicArray<_NestedArrayStructure, LogicValue>, LogicValue>(
        [2],
        ({name}) => TypedLogicArray<_NestedArrayStructure, LogicValue>(
          [3],
          _NestedArrayStructure.new,
          name: name,
        ),
      );
      final module = _NestedArrayBoundaryModule(source);
      await module.build();

      final inputFields = [
        (before: 1, lane0: 2, lane1: 3, sample0: 4, sample1: 5, after: 0),
        (before: 2, lane0: 4, lane1: 5, sample0: 1, sample1: 6, after: 1),
        (before: 3, lane0: 6, lane1: 7, sample0: 2, sample1: 0, after: 0),
        (before: 0, lane0: 1, lane1: 2, sample0: 3, sample1: 7, after: 1),
        (before: 3, lane0: 5, lane1: 1, sample0: 4, sample1: 2, after: 0),
        (before: 2, lane0: 7, lane1: 4, sample0: 5, sample1: 3, after: 1),
      ];
      final input = [
        for (final fields in inputFields)
          _nestedPacked(
            fields.before,
            fields.lane0,
            fields.lane1,
            fields.sample0,
            fields.sample1,
            fields.after,
          ),
      ];
      final output = <LogicValue>[];
      for (var outer = 0; outer < 2; outer++) {
        for (var inner = 0; inner < 3; inner++) {
          final fields = inputFields[(1 - outer) * 3 + (2 - inner)];
          output.add(
            _nestedPacked(
              fields.before,
              fields.lane1,
              fields.lane0,
              fields.sample1 ^ 6,
              fields.sample0 ^ 6,
              fields.after ^ 1,
            ),
          );
        }
      }
      final inputValue = LogicValue.ofIterable(input);
      final outputValue = LogicValue.ofIterable(output);
      final vectors = [
        Vector({'valuesIn': inputValue}, {'valuesOut': outputValue}),
      ];

      await SimCompare.checkFunctionalVector(module, vectors);
      final sv = module.generateSynth();
      expect(sv, contains('valuesIn[1][31:30]'));
      expect(sv, contains('valuesOut[0][31:30]'));
      expect(
        sv,
        contains(
          'assign valuesIn_0__0__lanes[0][2:0] = valuesIn[0][4:2];',
        ),
      );
      expect(sv, isNot(contains('// struct_slice')));
      final netlistJson = NetlistSynthesizer().synthesizeToJson(module);
      final netlist = jsonDecode(netlistJson) as Map<String, dynamic>;
      final modules = netlist['modules'] as Map<String, dynamic>;
      final child =
          modules['_NestedArrayBoundaryChild'] as Map<String, dynamic>;
      final parent =
          modules['_NestedArrayBoundaryModule'] as Map<String, dynamic>;
      final childPorts = child['ports'] as Map<String, dynamic>;
      final childInput = childPorts['valuesIn'] as Map<String, dynamic>;
      final childInputType = childInput['logic_type'] as Map<String, dynamic>;
      final childNetnames = child['netnames'] as Map<String, dynamic>;
      final firstLanes =
          childNetnames['valuesIn_0__0__lanes'] as Map<String, dynamic>;
      final firstSamples =
          childNetnames['valuesIn_0__0__samples'] as Map<String, dynamic>;
      final innerType = childInputType['elementType'] as Map<String, dynamic>;
      final elementType = innerType['elementType'] as Map<String, dynamic>;
      final fields =
          (elementType['fields'] as List<dynamic>).cast<Map<String, dynamic>>();
      final parentCells = parent['cells'] as Map<String, dynamic>;
      final childCellEntry = parentCells.entries.singleWhere(
        (entry) =>
            (entry.value as Map<String, dynamic>)['type'] ==
            '_NestedArrayBoundaryChild',
      );
      final childCell = childCellEntry.value as Map<String, dynamic>;
      final childConnections = childCell['connections'] as Map<String, dynamic>;

      expect(childInputType['arrayDims'], [2]);
      expect(innerType['arrayDims'], [3]);
      expect(
        fields.singleWhere((field) => field['name'] == 'lanes')['type'],
        containsPair('arrayDims', [2]),
      );
      final samplesType =
          fields.singleWhere((field) => field['name'] == 'samples')['type']
              as Map<String, dynamic>;
      expect(samplesType['arrayDims'], [2]);
      expect(
        samplesType['elementType'],
        containsPair('typeName', '_SampleStructure'),
      );
      expect(childConnections['valuesIn'], hasLength(90));
      expect(childConnections['valuesOut'], hasLength(90));
      expect(childCellEntry.key, 'unnamed_module');
      final firstLaneBits = (firstLanes['bits'] as List).cast<Object?>();
      final childCells = (child['cells'] as Map<String, dynamic>)
          .values
          .cast<Map<String, dynamic>>();
      final firstInputUnpack = childCells.singleWhere((cell) {
        if (cell['type'] != r'$struct_unpack') {
          return false;
        }
        final connections = cell['connections'] as Map<String, dynamic>;
        final lanes = (connections['lanes'] as List?)?.cast<Object?>();
        return lanes != null &&
            lanes.length == firstLaneBits.length &&
            lanes.indexed.every((entry) => entry.$2 == firstLaneBits[entry.$1]);
      });
      final unpackParameters =
          firstInputUnpack['parameters'] as Map<String, dynamic>;
      final unpackConnections =
          firstInputUnpack['connections'] as Map<String, dynamic>;
      expect(unpackParameters['FIELD_1_NAME'], 'lanes');
      expect(unpackParameters['FIELD_1_OFFSET'], 2);
      expect(unpackParameters['FIELD_1_WIDTH'], 6);
      expect(unpackConnections['lanes'], firstLanes['bits']);
      expect(unpackParameters['FIELD_2_NAME'], 'samples');
      expect(unpackParameters['FIELD_2_OFFSET'], 8);
      expect(unpackParameters['FIELD_2_WIDTH'], 6);
      expect(unpackConnections['samples'], firstSamples['bits']);
      final netlistNames = {
        for (final moduleDefinition
            in modules.values.cast<Map<String, dynamic>>()) ...[
          ...(moduleDefinition['ports'] as Map<String, dynamic>).keys,
          ...(moduleDefinition['netnames'] as Map<String, dynamic>).keys,
        ],
      };
      for (final name in [
        'valuesIn',
        'valuesOut',
        'valuesIn_0__0__lanes',
        'valuesIn_0__0__samples',
        'valuesOut_1__2__lanes',
      ]) {
        expect(sv, contains(name));
        expect(netlistNames, contains(name),
            reason: 'SV and netlist should preserve signal name $name.');
      }
      SimCompare.checkIverilogVector(module, vectors);
      SimCompare.checkVerilatorVector(module, vectors);

      await Simulator.reset();
      final mixedSource = TypedLogicArray<
          TypedLogicArray<_NestedArrayStructure, LogicValue>, LogicValue>(
        [2],
        ({name}) => TypedLogicArray<_NestedArrayStructure, LogicValue>(
          [3],
          ({name}) => _NestedArrayStructure(
            name: name,
            numUnpackedDimensions: 1,
          ),
          name: name,
          numUnpackedDimensions: 1,
        ),
        numUnpackedDimensions: 1,
      );
      final mixedModule = _NestedArrayBoundaryModule(mixedSource);
      await mixedModule.build();

      await SimCompare.checkFunctionalVector(mixedModule, vectors);
      final mixedSv = mixedModule.generateSynth();
      expect(
        mixedSv,
        contains('input logic [44:0] valuesIn [1:0]'),
      );
      expect(
        mixedSv,
        contains('output logic [44:0] valuesOut [1:0]'),
      );
      expect(
        mixedSv,
        contains('logic [2:0] valuesIn_0__0__lanes [1:0];'),
      );
      expect(
        mixedSv,
        contains('logic [2:0] valuesIn_0__0__samples [1:0];'),
      );
      final workaroundSv = mixedModule.generateSynth(
        configuration: _iverilogUnpackedArrayWorkaround,
      );
      expect(
        RegExp(
          RegExp.escape('output wire logic [44:0] valuesOut [1:0]'),
        ).allMatches(workaroundSv),
        hasLength(2),
      );
      expect(
        workaroundSv,
        contains('wire [44:0] valuesOut_0 [1:0];'),
      );
      final mixedNetlist = jsonDecode(
        NetlistSynthesizer().synthesizeToJson(mixedModule),
      ) as Map<String, dynamic>;
      expect(
        mixedNetlist['modules'],
        containsPair('_NestedArrayBoundaryModule', isA<Map<String, dynamic>>()),
      );
      SimCompare.checkIverilogVector(
        mixedModule,
        vectors,
        synthesizerConfiguration: _iverilogUnpackedArrayWorkaround,
      );
      SimCompare.checkVerilatorVector(mixedModule, vectors);
    }, tags: ['verilator']);

    test('simulates mixed nested arrays across a child boundary', () async {
      await Simulator.reset();
      final source =
          TypedLogicArray<TypedLogicArray<Logic, LogicValue>, LogicValue>(
        [2, 3],
        ({name}) => TypedLogicArray<Logic, LogicValue>(
          [4, 5],
          ({name}) => Logic(name: name, width: 8),
          name: name,
          numUnpackedDimensions: 1,
        ),
        numUnpackedDimensions: 1,
      );
      final module = _MixedNestedArrayModule(source);
      await module.build();
      final input = LogicValue.ofIterable([
        for (var value = 1; value <= 120; value++) LogicValue.ofInt(value, 8),
      ]);
      final expected = LogicValue.ofIterable([
        for (var group = 0; group < 6; group++)
          for (var value = 20; value >= 1; value--)
            LogicValue.ofInt(group * 20 + value, 8),
      ]);

      final vectors = [
        Vector({'valuesIn': input}, {'valuesOut': expected})
      ];
      await SimCompare.checkFunctionalVector(module, vectors);
      final sv = module.generateSynth();
      expect(
        sv,
        contains('input logic [2:0][159:0] valuesIn [1:0]'),
      );
      expect(
        sv,
        contains('output logic [2:0][159:0] valuesOut [1:0]'),
      );
      expect(
        sv,
        contains('valuesOut[1][2][159:152] = '
            'valuesIn[1][2][7:0]'),
      );
      final workaroundSv = module.generateSynth(
        configuration: _iverilogUnpackedArrayWorkaround,
      );
      expect(
        workaroundSv,
        contains('output wire logic [2:0][159:0] valuesOut [1:0]'),
      );
      final netlist = jsonDecode(NetlistSynthesizer().synthesizeToJson(module))
          as Map<String, dynamic>;
      final modules = netlist['modules'] as Map<String, dynamic>;
      final top = modules['_MixedNestedArrayModule'] as Map<String, dynamic>;
      final ports = top['ports'] as Map<String, dynamic>;
      for (final portName in ['valuesIn', 'valuesOut']) {
        final port = ports[portName] as Map<String, dynamic>;
        final type = port['logic_type'] as Map<String, dynamic>;
        final outerElementType = type['elementType'] as Map<String, dynamic>;
        final innerType =
            outerElementType['elementType'] as Map<String, dynamic>;
        expect(type['arrayDims'], [2, 3]);
        expect(type['elementWidth'], 160);
        expect(outerElementType['arrayDims'], [3]);
        expect(innerType['arrayDims'], [4, 5]);
        expect(innerType['elementWidth'], 8);
        expect(port['bits'], hasLength(960));
      }
      SimCompare.checkIverilogVector(
        module,
        vectors,
        synthesizerConfiguration: _iverilogUnpackedArrayWorkaround,
      );
      SimCompare.checkVerilatorVector(module, vectors);
      expect(source.numUnpackedDimensions, 1);
      expect(source.at([1, 2]).numUnpackedDimensions, 1);
      expect(source.at([1, 2]).at([3, 4]).width, 8);
    }, tags: ['verilator']);
  });
}
