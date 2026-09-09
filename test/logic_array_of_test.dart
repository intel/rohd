// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
// ignore_for_file: prefer_const_constructors
// ignore_for_file: prefer_const_literals_to_create_immutables
//
// logic_array_of_test.dart
// Tests for typed logic and logic value arrays.
//
// 2026 July 21
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class _SampleStructure extends LogicStructure {
  final Logic low;
  final Logic high;

  factory _SampleStructure({String? name}) => _SampleStructure._(
        Logic(name: 'low'),
        Logic(name: 'high', width: 2),
        name: name ?? 'sample',
      );

  _SampleStructure._(this.low, this.high, {required String name})
      : super([low, high], name: name);

  @override
  _SampleStructure clone({String? name}) =>
      _SampleStructure(name: name ?? this.name);
}

class _SpecialLogic extends Logic {
  _SpecialLogic({super.name}) : super(width: 2);

  @override
  Logic clone({String? name}) => Logic(name: name ?? this.name, width: width);
}

class _TypedArrayPortModule extends Module {
  LogicArrayOf<_SampleStructure> get valuesOut =>
      output('valuesOut') as LogicArrayOf<_SampleStructure>;

  _TypedArrayPortModule(LogicArrayOf<_SampleStructure> valuesIn) {
    valuesIn = addTypedInput('valuesIn', valuesIn);
    final valuesOut = addTypedOutput('valuesOut', valuesIn.clone);
    for (final (index, source) in valuesIn.arrayElements.indexed) {
      final destination = valuesOut.arrayElements[index];
      destination.low <= source.low;
      destination.high <= ~source.high;
    }
  }
}

class _TypedArrayInterface extends Interface<_TypedArrayDirection> {
  _TypedArrayInterface() {
    setPorts([
      LogicArrayOf<_SampleStructure>(
        [2],
        _SampleStructure.new,
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
  LogicArrayOf<_SampleStructure> get valuesOut =>
      output('valuesOut') as LogicArrayOf<_SampleStructure>;

  _TypedArrayHierarchy(LogicArrayOf<_SampleStructure> source) {
    final valuesIn = addTypedInput('valuesIn', source);
    final child = _TypedArrayPortModule(valuesIn);
    addTypedOutput('valuesOut', valuesIn.clone).gets(child.valuesOut);
  }
}

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
  group('LogicArrayOf', () {
    test('keeps structured leaves at the array boundary', () {
      final values = LogicArrayOf<_SampleStructure>(
        [2, 3],
        _SampleStructure.new,
        dimensionNames: const ['row_', 'column_'],
      );

      expect(values, isA<LogicArrayOf<_SampleStructure>>());
      expect(values.dimensions, equals([2, 3]));
      expect(values.elementWidth, 3);
      expect(values.arrayElements, hasLength(6));
      expect(values.arrayElements, everyElement(isA<_SampleStructure>()));
      expect(values.leafElements, hasLength(12));
      expect(values.at([1, 2]), same(values.arrayElements[5]));
      expect(values.indexedElements.last.$1, equals([1, 2]));
      expect(
        values.reshape([3, 2]).dimensionNames,
        equals(['row_', 'column_']),
      );
      expect(
        values.transpose2D().dimensionNames,
        equals(['column_', 'row_']),
      );
    });

    test('provides typed indexing, cloning, and packed conversions', () {
      final values = LogicArrayOf<Logic>(
        [2, 2],
        ({name}) => Logic(name: name, width: 8),
      );
      final packed = values.toLogicArray(name: 'packed');
      final clone = values.clone(name: 'clone');

      expect(values.at([1, 0]), same(values.arrayElements[2]));
      expect(packed.dimensions, equals([2, 2]));
      expect(packed.elementWidth, 8);
      expect(clone, isA<LogicArrayOf<Logic>>());
      expect(clone.name, 'clone');
      expect(clone.arrayElements, hasLength(4));
      expect(
        () => values.getsPackedValues(LogicArray([4], 8)),
        throwsA(isA<LogicConstructionException>()),
      );
      expect(
        () => values.getsPackedValues(LogicArray([2, 2], 4)),
        throwsA(isA<LogicConstructionException>()),
      );
    });

    test('derives the net kind for empty multidimensional typed arrays', () {
      var logicBuilds = 0;
      var netBuilds = 0;
      final logicValues = LogicArrayOf<Logic>(
        [2, 0],
        ({name}) {
          logicBuilds++;
          return Logic(name: name, width: 8);
        },
      );
      final netValues = LogicArrayOf<LogicNet>(
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
        isA<LogicArrayOf<Logic>>(),
      );
    });

    test('preserves unpacked dimensions through cloning', () {
      final values = LogicArrayOf<Logic>(
        [2, 3],
        ({name}) => Logic(name: name, width: 4),
        numUnpackedDimensions: 1,
      );

      expect(values.clone().numUnpackedDimensions, 1);
      expect(
        values.named('renamed').numUnpackedDimensions,
        1,
      );
    });

    test('recursively flattens nested array dimensions with typed leaves', () {
      final nested = LogicArrayOf<LogicArray>(
        [2, 2],
        ({name}) => LogicArray([3, 2], 4, name: name),
      );
      final flattened = nested.flattenNestedDimensions<Logic>(name: 'flat');
      final source = nested.at([1, 0]).at([2, 1]);
      final target = flattened.at([1, 0, 2, 1]);

      expect(flattened.dimensions, equals([2, 2, 3, 2]));
      expect(flattened.elementWidth, 4);
      expect(flattened.arrayElements, hasLength(24));
      expect(target, isA<Logic>());
      expect(target.srcConnections, contains(source));
    });

    test('flattens every nested array layer', () {
      final nested = LogicArrayOf<LogicArrayOf<LogicArray>>(
        [2],
        ({name}) => LogicArrayOf<LogicArray>(
          [3],
          ({name}) => LogicArray([4], 2, name: name),
          name: name,
        ),
      );
      final flattened = nested.flattenNestedDimensions<Logic>();
      final source = nested.at([1]).at([2]).at([3]);
      final target = flattened.at([1, 2, 3]);

      expect(flattened.dimensions, equals([2, 3, 4]));
      expect(flattened.arrayElements, hasLength(24));
      expect(target.srcConnections, contains(source));
    });

    test('flattens empty arrays and leaves without specialized clones', () {
      final empty = LogicArrayOf<Logic>(
        [2, 0],
        ({name}) => Logic(name: name, width: 4),
      );
      final emptyNested = LogicArrayOf<LogicArrayOf<Logic>>(
        [0],
        ({name}) => LogicArrayOf<Logic>(
          [3],
          ({name}) => Logic(name: name, width: 2),
          name: name,
        ),
      );
      final specialized = LogicArrayOf<_SpecialLogic>([2], _SpecialLogic.new);

      final flattenedEmpty = empty.flattenNestedDimensions<Logic>();
      final flattenedNested = emptyNested.flattenNestedDimensions<Logic>();
      final flattenedSpecialized =
          specialized.flattenNestedDimensions<_SpecialLogic>();

      expect(flattenedEmpty.dimensions, [2, 0]);
      expect(flattenedEmpty.elementWidth, 4);
      expect(flattenedEmpty.arrayElements, isEmpty);
      expect(flattenedNested.dimensions, [0, 3]);
      expect(flattenedNested.elementWidth, 2);
      expect(flattenedNested.arrayElements, isEmpty);
      expect(
        flattenedSpecialized.arrayElements,
        everyElement(isA<_SpecialLogic>()),
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
      expect(
        () => LogicArrayOf<Logic>(
          [2, 2],
          Logic.new,
          dimensionNames: const ['row.', 'column_'],
        ),
        throwsA(isA<LogicConstructionException>()),
      );
      expect(
        () => LogicArrayOf<Logic>(
          [2, 2],
          Logic.new,
          dimensionNames: const ['row_', 'row_'],
        ),
        throwsA(isA<LogicConstructionException>()),
      );
      expect(
        () => LogicArrayOf<Const>(
          [2],
          ({name}) => Const(0, width: 1),
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

    test('preserves naming when named', () {
      final values = LogicArrayOf<Logic>(
        [2],
        Logic.new,
        name: 'values',
        naming: Naming.mergeable,
      );

      final renamed = values.named('renamed', naming: Naming.reserved);

      expect(renamed.name, 'renamed');
      expect(renamed.naming, Naming.reserved);
    });

    test('matches LogicArray clone naming policy', () {
      final typed = LogicArrayOf<Logic>(
        [2],
        Logic.new,
        name: 'typedValues',
        naming: Naming.reserved,
      );
      final ordinary = LogicArray(
        [2],
        1,
        name: 'ordinaryValues',
        naming: Naming.reserved,
      );

      expect(typed.clone().naming, ordinary.clone().naming);
      expect(
        typed.clone(name: 'typedClone').naming,
        ordinary.clone(name: 'ordinaryClone').naming,
      );
    });

    test('drives, injects, and captures packed and typed values', () async {
      addTearDown(Simulator.reset);
      const codec = LogicValueCodec<int>(
        decode: _decodeLogicValue,
        encode: _encodeLogicValue,
      );
      final values = LogicArrayOf<Logic>(
        [2],
        ({name}) => Logic(name: name, width: 8),
      );
      final packedValues = LogicValueArray.fromInts([12, 34], elementWidth: 8);
      final typedValues = LogicValueArrayOf<int>(
        [90, 123],
        codec: codec,
      );

      expect(packedValues.putInto(values), same(values));
      expect(
        values.value.arrayValues.map((value) => value.toInt()),
        [12, 34],
      );

      values.put(LogicValue.ofInt(0x4e38, 16));
      expect(
        values.value.arrayValues.map((value) => value.toInt()),
        [56, 78],
      );
      expect(
        () => values.put(typedValues, fill: true),
        throwsArgumentError,
      );

      values.inject(typedValues);
      await Simulator.run();
      expect(
        LogicValueArrayOf<int>.fromLogicValueArray(
          values.value,
          codec: codec,
        ).arrayValues,
        [90, 123],
      );
    });

    test('preserves specialized leaves in typed input and output ports', () {
      final source = LogicArrayOf<_SampleStructure>(
        [2, 3],
        _SampleStructure.new,
      );
      final module = _TypedArrayPortModule(source);
      final valuesIn =
          module.input('valuesIn') as LogicArrayOf<_SampleStructure>;

      expect(valuesIn, isA<LogicArrayOf<_SampleStructure>>());
      expect(valuesIn.dimensions, [2, 3]);
      expect(valuesIn.at([1, 2]), isA<_SampleStructure>());
      expect(module.valuesOut, isA<LogicArrayOf<_SampleStructure>>());
      expect(module.valuesOut.at([1, 2]).low.width, 1);
      expect(module.valuesOut.at([1, 2]).high.width, 2);
    });

    test('preserves typed arrays through interfaces and synthesis', () async {
      final source = LogicArrayOf<_SampleStructure>(
        [2, 2],
        _SampleStructure.new,
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
        isA<LogicArrayOf<_SampleStructure>>(),
      );
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
      final flat = LogicValueArray.fromFlat([2, 2], 8, leaves);
      final nestedInts = LogicValueArray.fromInts([
        [1, 2],
        [3, 4],
      ], elementWidth: 8);
      final flatInts = LogicValueArray.fromFlatInts([2, 2], 8, [1, 2, 3, 4]);

      expect(nested.dimensions, [2, 2]);
      expect(nested.elementWidth, 8);
      expect(nested.elementCount, 4);
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
      expect(values.flatIndexOf([1, 2]), 5);
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

    test('round-trips slices with an empty inner dimension', () {
      final values = LogicValueArray.fromFlat([2, 0], 8, const []);
      final slices = values.majorSlices.toList(growable: false);

      expect(slices, hasLength(2));
      expect(slices.map((slice) => slice.dimensions), [
        [0],
        [0],
      ]);
      expect(slices.map((slice) => slice.elementWidth), [8, 8]);
      expect(LogicValueArray.stack(slices).dimensions, [2, 0]);
      expect(values.mapMajorSlices((slice) => slice).dimensions, [2, 0]);
    });

    test('uses packed LogicValue semantics independent of shape', () {
      final shaped = LogicValueArray.fromFlatInts([2], 4, [1, 2]);
      final reshaped = LogicValueArray.fromFlatInts([1, 2], 4, [1, 2]);
      final packed = LogicValue.ofInt(0x21, 8);
      final mask = LogicValue.ofInt(0xf0, 8);
      final zeros = LogicValueArray.fromFlatInts([2], 4, [0, 0]);

      expect(shaped, packed);
      expect(packed, shaped);
      expect(shaped, reshaped);
      expect(shaped.hashCode, packed.hashCode);
      expect(shaped[0], LogicValue.one);
      expect(shaped & mask, packed & mask);
      expect(mask & shaped, mask & packed);
      expect(shaped | mask, packed | mask);
      expect(mask | shaped, mask | packed);
      expect(shaped ^ mask, packed ^ mask);
      expect(mask ^ shaped, mask ^ packed);
      expect(shaped + LogicValue.one.zeroExtend(8),
          packed + LogicValue.one.zeroExtend(8));
      expect(LogicValue.one.zeroExtend(8) + shaped,
          LogicValue.one.zeroExtend(8) + packed);
      expect(LogicValue.ofIterable([zeros]), zeros.packed);
      expect(
        LogicValue.ofIterable([zeros, shaped]),
        LogicValue.ofIterable([zeros.packed, shaped.packed]),
      );
      expect({shaped, packed}, hasLength(1));
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
        () => LogicValueArray.fromFlat([2, 2], 8, [one]),
        throwsArgumentError,
      );
      expect(
        () => LogicValueArray.fromInts(const [], elementWidth: 8),
        throwsArgumentError,
      );
      expect(() => LogicValueArray.fromFlat(const [], 8, const []),
          throwsArgumentError);
    });
  });

  group('LogicValueArrayOf', () {
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
      final nested = LogicValueArrayOf<List<int>>([
        [leaves[0], leaves[1]],
        [leaves[2], leaves[3]],
      ], codec: codec);
      final flat = LogicValueArrayOf<List<int>>.fromFlat(
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
      final values = LogicValueArrayOf<int>.fromLogicValueArray(
        packed,
        codec: codec,
      );

      expect(values.at([1, 1]), 5);
      expect(values.map((value) => value + 1).at([1, 1]), 6);
      expect(values.reshape([3, 2]).at([2, 1]), 6);
      expect(values.transpose2D().arrayValues, [1, 4, 2, 5, 3, 6]);
      expect(values.toLogicArray().dimensions, [2, 3]);
    });

    test('supports slices, indexed mapping, and compatible stacking', () {
      const codec = LogicValueCodec<int>(
        decode: _decodeLogicValue,
        encode: _encodeLogicValue,
      );
      final values = LogicValueArrayOf<int>([
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
        LogicValueArrayOf<int>.stack(values.majorSlices).arrayValues,
        values.arrayValues,
      );
      expect(values.packed, LogicValue.ofInt(0x04030201, 32));
    });

    test('normalizes lossy codecs at construction and preserves values', () {
      const codec = LogicValueCodec<double>(
        decode: _decodeRoundedLogicValue,
        encode: _encodeRoundedLogicValue,
      );
      final values = LogicValueArrayOf<double>([
        [1.2, 2.4],
        [3.6, 4.8],
      ], codec: codec);

      expect(values.arrayValues, [1.0, 2.0, 4.0, 5.0]);
      expect(values.reshape([4]).arrayValues, values.arrayValues);
      expect(
        LogicValueArrayOf<double>.stack(values.majorSlices).arrayValues,
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
      final first = LogicValueArrayOf<int>.fromFlat(
        [1],
        8,
        [1],
        codec: firstCodec,
      );
      final second = LogicValueArrayOf<int>.fromFlat(
        [1],
        8,
        [2],
        codec: secondCodec,
      );

      expect(
        () => LogicValueArrayOf<int>.stack([first, second]),
        throwsArgumentError,
      );
    });

    test('round-trips typed slices with an empty inner dimension', () {
      const codec = LogicValueCodec<int>(
        decode: _decodeLogicValue,
        encode: _encodeLogicValue,
      );
      final values = LogicValueArrayOf<int>.fromFlat(
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
        LogicValueArrayOf<int>.stack(slices).dimensions,
        [2, 0],
      );
      expect(values.mapMajorSlices((slice) => slice).dimensions, [2, 0]);
    });
  });
}
