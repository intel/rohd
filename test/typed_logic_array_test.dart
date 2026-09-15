// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
// ignore_for_file: prefer_const_constructors
// ignore_for_file: prefer_const_literals_to_create_immutables
//
// typed_logic_array_test.dart
// Tests for typed logic and logic value arrays.
//
// 2026 July 21
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

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

class _NestedNetArrayStructure extends LogicStructure {
  final LogicNet before;
  final LogicArray lanes;
  final LogicNet after;

  factory _NestedNetArrayStructure({
    String? name,
    int numUnpackedDimensions = 0,
  }) =>
      _NestedNetArrayStructure._(
        LogicNet(name: 'before', width: 2),
        LogicArray.net(
          [2],
          3,
          name: 'lanes',
          numUnpackedDimensions: numUnpackedDimensions,
        ),
        LogicNet(name: 'after'),
        name: name ?? 'nestedNet',
      );

  _NestedNetArrayStructure._(
    this.before,
    this.lanes,
    this.after, {
    required String name,
  }) : super([before, lanes, after], name: name);

  @override
  _NestedNetArrayStructure clone({String? name}) => _NestedNetArrayStructure(
        name: name ?? this.name,
        numUnpackedDimensions: lanes.numUnpackedDimensions,
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

class _NestedStructuredInOutDriveModule extends Module {
  late final TypedLogicArray<_NestedNetArrayStructure, LogicValue> bus;

  _NestedStructuredInOutDriveModule(
      TypedLogicArray<_NestedNetArrayStructure, LogicValue> source,
      Logic enable,
      Logic driveValue) {
    bus = addTypedInOut('bus', source);
    enable = addInput('enable', enable);
    driveValue = addInput('driveValue', driveValue, width: bus.width);
    final child = _NestedStructuredInOutDriveChild(bus, enable, driveValue);
    addOutput('observed', width: bus.width).gets(child.observed);
  }
}

class _NestedStructuredInOutDriveChild extends Module {
  late final Logic observed;

  _NestedStructuredInOutDriveChild(
      TypedLogicArray<_NestedNetArrayStructure, LogicValue> source,
      Logic enable,
      Logic driveValue) {
    final bus = addTypedInOut('bus', source);
    enable = addInput('enable', enable);
    driveValue = addInput('driveValue', driveValue, width: bus.width);
    var driveOffset = 0;
    for (final leaf in bus.leafElements) {
      leaf <=
          TriStateBuffer(
            driveValue.getRange(driveOffset, driveOffset + leaf.width),
            enable: enable,
          ).out;
      driveOffset += leaf.width;
    }
    observed = addOutput('observed', width: bus.width);
    Combinational([observed < bus.packed]);
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

class _TypedInputModule<T extends Logic> extends Module {
  late final T values;

  _TypedInputModule(T source) {
    values = addTypedInput('values', source);
  }
}

int _decodeLogicValue(LogicValue value) => value.toInt();

LogicValue _encodeLogicValue(int value) => LogicValue.ofInt(value, 8);

double _decodeRoundedLogicValue(LogicValue value) => value.toInt().toDouble();

LogicValue _encodeRoundedLogicValue(double value) =>
    LogicValue.ofInt(value.round(), 8);

List<int> _decodeListLogicValue(LogicValue value) => [value.toInt()];

LogicValue _encodeListLogicValue(List<int> value) =>
    LogicValue.ofInt(value.single, 8);

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
        contains('output wire logic [44:0] valuesOut [1:0]'),
      );
      expect(
        mixedSv,
        contains('logic [2:0] valuesIn_0__0__lanes [1:0];'),
      );
      expect(
        mixedSv,
        contains('logic [2:0] valuesIn_0__0__samples [1:0];'),
      );
      final mixedNetlist = jsonDecode(
        NetlistSynthesizer().synthesizeToJson(mixedModule),
      ) as Map<String, dynamic>;
      expect(
        mixedNetlist['modules'],
        containsPair('_NestedArrayBoundaryModule', isA<Map<String, dynamic>>()),
      );
      SimCompare.checkIverilogVector(mixedModule, vectors);
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
        contains('output wire logic [2:0][159:0] valuesOut [1:0]'),
      );
      expect(
        sv,
        contains('valuesOut[1][2][159:152] = '
            'valuesIn[1][2][7:0]'),
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
      SimCompare.checkIverilogVector(module, vectors);
      SimCompare.checkVerilatorVector(module, vectors);
      expect(source.numUnpackedDimensions, 1);
      expect(source.at([1, 2]).numUnpackedDimensions, 1);
      expect(source.at([1, 2]).at([3, 4]).width, 8);
    }, tags: ['verilator']);

    test('drives and releases a nested structured typed inout array', () async {
      await Simulator.reset();
      final source = TypedLogicArray<_NestedNetArrayStructure, LogicValue>(
        [2],
        ({name}) => _NestedNetArrayStructure(
          name: name,
          numUnpackedDimensions: 1,
        ),
      );
      final enable = Logic();
      final driveValue = Logic(width: source.width);
      final module =
          _NestedStructuredInOutDriveModule(source, enable, driveValue);
      await module.build();
      final vectors = [
        Vector(
          {'bus': 0x2a155, 'enable': 0, 'driveValue': 0},
          {'observed': 0x2a155},
        ),
        Vector(
          {'bus': LogicValue.z, 'enable': 1, 'driveValue': 0x15caa},
          {'observed': 0x15caa},
        ),
        Vector(
          {'bus': LogicValue.z, 'enable': 0, 'driveValue': 0},
          {'bus': LogicValue.z},
        ),
      ];
      await SimCompare.checkFunctionalVector(module, vectors);
      final sv = module.generateSynth();
      expect(sv, contains('inout wire [1:0][8:0] bus'));
      expect(source.numUnpackedDimensions, 0);
      expect(source.at([0]).lanes.numUnpackedDimensions, 1);
      SimCompare.checkIverilogVector(module, vectors);
      final netlist = jsonDecode(
        NetlistSynthesizer().synthesizeToJson(module),
      ) as Map<String, dynamic>;
      final modules = netlist['modules'] as Map<String, dynamic>;
      final top =
          modules['_NestedStructuredInOutDriveModule'] as Map<String, dynamic>;
      final ports = top['ports'] as Map<String, dynamic>;
      final busPort = ports['bus'] as Map<String, dynamic>;
      expect(ports, contains('observed'));
      expect(busPort['direction'], 'inout');
      expect(busPort['bits'], hasLength(source.width));
      // Verilator does not support the bidirectional `tran` primitive needed
      // to model four-state drive and release.
    });
  });

  group('LogicValueArray', () {
    test('constructs equivalent nested and flat row-major values', () {
      final leaves = [
        for (var value = 1; value <= 4; value++) LogicValue.ofInt(value, 8),
      ];
      final nested = LogicValueArray([
        [leaves[0], leaves[1]],
        [leaves[2], leaves[3]],
      ]);
      final flat = LogicValueArray.fromFlat([2, 2], leaves);
      final nestedInts = LogicValueArray.fromInts([
        [1, 2],
        [3, 4],
      ], elementWidth: 8);
      final flatInts = LogicValueArray.fromFlatInts(
        [2, 2],
        [1, 2, 3, 4],
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
      final values = LogicValueArray.fromInts([
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
        [2, 3],
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
        [2, 0],
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
        () => LogicValueArray.stack(<LogicValueArray>[]),
        throwsArgumentError,
      );
      expect(
        () => TypedLogicValueArray<int>.stack(<TypedLogicValueArray<int>>[]),
        throwsArgumentError,
      );
      expect(
        () => LogicValueArray.stack(
          LogicValueArray.fromFlat([0, 2], const [], elementWidth: 8)
              .majorSlices,
        ),
        throwsArgumentError,
      );
    });

    test('round-trips slices with an empty inner dimension', () {
      final values =
          LogicValueArray.fromFlat([2, 0], const [], elementWidth: 8);
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
        () => LogicValueArray.fromFlat([2, 2], [one]),
        throwsArgumentError,
      );
      expect(
        LogicValueArray.fromFlat(
          [2],
          [LogicValue.ofInt(1, 4), LogicValue.ofInt(2, 4)],
        ).elementWidth,
        4,
      );
      expect(
        LogicValueArray.fromFlat(
          [2],
          [LogicValue.ofInt(1, 4), LogicValue.ofInt(2, 4)],
          elementWidth: 4,
        ).elementWidth,
        4,
      );
      expect(
        () => LogicValueArray.fromFlat(
          [2],
          [LogicValue.ofInt(1, 4), LogicValue.ofInt(2, 3)],
        ),
        throwsArgumentError,
      );
      expect(
        () => LogicValueArray.fromFlat(
          [2],
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
        LogicValueArray.fromFlat([2, 0], const [], elementWidth: 8)
            .elementWidth,
        8,
      );
      expect(
        () => LogicValueArray.fromFlat([2, 0], const []),
        throwsArgumentError,
      );
    });

    test('rejects invalid value indices, shapes, widths, and stacks', () {
      final values = LogicValueArray.fromFlatInts(
        [2, 2],
        [1, 2, 3, 4],
        elementWidth: 8,
      );
      final oneDimensional = LogicValueArray.fromFlatInts(
        [4],
        [1, 2, 3, 4],
        elementWidth: 8,
      );
      final threeDimensional = LogicValueArray.fromFlatInts(
        [1, 2, 2],
        [1, 2, 3, 4],
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
        () => LogicValueArray.fromFlat([-1], const [], elementWidth: 8),
        throwsArgumentError,
      );
      expect(
        () => LogicValueArray.fromFlat([1], const [], elementWidth: -1),
        throwsArgumentError,
      );
      expect(
        () => LogicValueArray.generate(
          [1],
          (indices) => LogicValue.ofInt(indices.single, 4),
          elementWidth: 8,
        ),
        throwsArgumentError,
      );
      expect(
        () => LogicValueArray.stack([
          LogicValueArray.fromFlatInts([2], [1, 2], elementWidth: 8),
          LogicValueArray.fromFlatInts([1, 2], [3, 4], elementWidth: 8),
        ]),
        throwsArgumentError,
      );
      expect(
        () => LogicValueArray.stack([
          LogicValueArray.fromFlatInts([2], [1, 2], elementWidth: 8),
          LogicValueArray.fromFlatInts([2], [3, 4], elementWidth: 4),
        ]),
        throwsArgumentError,
      );
    });
  });

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
          [
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
        [2, 2],
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
      final packed = LogicValueArray.fromInts([
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
      final values = TypedLogicValueArray<int>([
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
      final values = TypedLogicValueArray<double>([
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
      final firstCodec = LogicValueCodec<int>(
        decode: _decodeLogicValue,
        encode: _encodeLogicValue,
      );
      final secondCodec = LogicValueCodec<int>(
        decode: _decodeLogicValue,
        encode: _encodeLogicValue,
      );
      final first = TypedLogicValueArray<int>.fromFlat(
        [1],
        8,
        [1],
        codec: firstCodec,
      );
      final second = TypedLogicValueArray<int>.fromFlat(
        [1],
        8,
        [2],
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
        [2, 0],
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
