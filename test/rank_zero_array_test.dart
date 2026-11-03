// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rank_zero_array_test.dart
// Tests for scalar-shaped typed arrays and connected scalar views.
//
// 2026 October 21
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class _Word extends LogicStructure {
  Logic get data => elements[0];
  Logic get flag => elements[1];

  _Word({String? name})
      : super([Logic(name: 'data', width: 3), Logic(name: 'flag')],
            name: name ?? 'word');

  @override
  _Word clone({String? name}) => _Word(name: name ?? this.name);
}

enum _State { idle, busy }

class _ScalarModule<T extends Logic> extends Module {
  _ScalarModule(TypedLogicArray<T, LogicValue> source, {bool view = false}) {
    final input = addTypedInput('source', source);
    final output = addTypedOutput('result', input.clone);
    final connected = view
        ? TypedLogicArray<T, LogicValue>.fromScalar(input.scalar,
            valueCodec: input.valueCodec, name: 'view')
        : input;
    output <= connected;
  }
}

class _ScalarFieldModule extends Module {
  _ScalarFieldModule(TypedLogicArray<_Word, LogicValue> source) {
    final input = addTypedInput('source', source);
    addOutput('data', width: 3) <= input.scalar.data;
    addOutput('flag') <= input.scalar.flag;
  }
}

class _ScalarRegister extends Module {
  _ScalarRegister(TypedLogicArray<_Word, LogicValue> source) {
    final clk = addInput('clk', Logic());
    final reset = addInput('reset', Logic());
    final input = addTypedInput('source', source);
    final output = addTypedOutput('result', input.clone);
    final selected =
        mux(Const(1), input, input.clone()..gets(Const(0, width: input.width)));
    output <= flop(clk, selected, reset: reset);
  }
}

class _ScalarNetModule extends Module {
  _ScalarNetModule(TypedLogicArray<LogicNet, LogicValue> source) {
    final data = addInput('data', Logic(width: 4), width: 4);
    final bus = addTypedInOut('bus', source);
    bus.scalar <= data;
    addOutput('observed', width: 4) <= bus.scalar;
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('rank zero traversal, scalar access, snapshots and clones', () {
    final source =
        TypedLogicArray<_Word, LogicValue>([], _Word.new, name: 'source');
    source.scalar.data.put(5);
    source.scalar.flag.put(1);
    expect(source.dimensions, isEmpty);
    expect(source.width, 4);
    expect(source.elementWidth, 4);
    expect(source.arrayElements, [same(source.scalar)]);
    expect(source.at([]), same(source.scalar));
    expect(source.indexedElements.single.$1, isEmpty);
    expect(source.indexedElements.single.$2, same(source.scalar));
    expect(source.leafElements, hasLength(2));
    expect(source.scalar.structureName, 'source');
    expect(source.scalar.data.structureName, 'source.data');
    expect(source.value.scalar.toInt(), 13);
    expect(source.value.at([]).toInt(), 13);
    expect(source.value.indexedValues.single.$1, isEmpty);
    final clone = source.clone(name: 'copy');
    expect(clone.dimensions, isEmpty);
    expect(clone.scalar, isA<_Word>());
    expect(clone.scalar, isNot(same(source.scalar)));
    expect(clone.scalar.structureName, 'copy');
    final named = source.named('alias');
    expect(named.value, source.value);
    expect(() => source.at([0]), throwsRangeError);
    expect(() => source.majorSlices.toList(), throwsStateError);
  });

  test('rank zero differs from an empty or singleton dimension', () {
    final zero = TypedLogicArray<Logic, LogicValue>([], Logic.new);
    final empty = TypedLogicArray<Logic, LogicValue>([0], Logic.new);
    final singleton = TypedLogicArray<Logic, LogicValue>([1], Logic.new);
    expect(zero.arrayElements, hasLength(1));
    expect(empty.arrayElements, isEmpty);
    expect(singleton.arrayElements, hasLength(1));
    expect(() => empty.scalar, throwsStateError);
    expect(() => singleton.scalar, throwsStateError);
    expect(() => singleton.value.scalar, throwsStateError);
    expect(
        () => TypedLogicArray<Logic, LogicValue>([], Logic.new,
            numUnpackedDimensions: 1),
        throwsA(isA<LogicConstructionException>()));
    expect(
        () => TypedLogicArray<Logic, LogicValue>([], Logic.new,
            dimensionNames: ['axis']),
        throwsA(isA<LogicConstructionException>()));
  });

  test('fromScalar connects a clone without reparenting the source', () {
    final parent = TypedLogicArray<_Word, LogicValue>([2], _Word.new);
    final source = parent.at([1]);
    final view = TypedLogicArray<_Word, LogicValue>.fromScalar(source,
        valueCodec: parent.valueCodec, name: 'view');
    expect(source.parentStructure, same(parent));
    expect(view.scalar, isNot(same(source)));
    expect(view.scalar.parentStructure, same(view));
    source.data.put(6);
    source.flag.put(1);
    expect(view.value.scalar.toInt(), 14);
    source.data.put(2);
    expect(view.value.scalar.toInt(), 10);
  });

  test('rank zero preserves enum mappings and nested array leaves', () {
    final state = TypedLogicArray<LogicEnum<_State>, LogicValue>(
        [], ({name}) => LogicEnum(_State.values, name: name));
    state.scalar.put(_State.busy);
    expect(state.scalar.valueEnum, _State.busy);
    expect(state.clone().scalar.mapping, state.scalar.mapping);
    final nested = TypedLogicArray<LogicArray, LogicValue>(
        [], ({name}) => LogicArray([2], 3, name: name));
    expect(nested.arrayElements, hasLength(1));
    expect(nested.scalar.dimensions, [2]);
    expect(nested.leafElements, hasLength(2));
    nested.scalar.elements[0].put(0);
    nested.scalar.elements[1].put(5);
    expect(nested.value.scalar.toInt(), 5 << 3);
  });

  test('rank zero value counts, codecs, mapping, reshape and stack', () {
    final codec = LogicValueCodec<({LogicValue bits})>(
        decode: (value) => (bits: value), encode: (value) => value.bits);
    final value = TypedLogicValueArray<({LogicValue bits})>.fromFlat(
        const [], 4, [(bits: LogicValue.ofInt(7, 4))],
        codec: codec);
    expect(value.scalar.bits.toInt(), 7);
    expect(value.at([]).bits.toInt(), 7);
    expect(value.map((v) => (bits: ~v.bits)).scalar.bits.toInt(), 8);
    expect(value.reshape([1]).reshape([]).scalar.bits.toInt(), 7);
    expect(TypedLogicValueArray.stack([value, value]).dimensions, [2]);
    expect(
        () => TypedLogicValueArray<LogicValue>.fromFlat(const [], 4, const [],
            codec: LogicValueCodec.logicValue),
        throwsArgumentError);
    expect(
        () => TypedLogicValueArray<LogicValue>.fromPacked(
            const [], 4, [LogicValue.ofInt(1, 4), LogicValue.ofInt(2, 4)],
            codec: LogicValueCodec.logicValue),
        throwsArgumentError);
  });

  for (final view in [false, true]) {
    for (final structured in [false, true]) {
      // Rank-zero declarations have no array index; field reads still address
      // the appropriate packed bits of structured leaves.
      test('rank-zero typed ports structured=$structured view=$view', () async {
        final source = structured
            ? TypedLogicArray<_Word, LogicValue>([], _Word.new)
            : TypedLogicArray<Logic, LogicValue>(
                [], ({name}) => Logic(width: 4, name: name));
        final module = _ScalarModule(source, view: view);
        await module.build();
        final vectors = [
          Vector({'source': 0}, {'result': 0}),
          Vector({'source': 13}, {'result': 13}),
          Vector({'source': 6}, {'result': 6}),
        ];
        await SimCompare.checkFunctionalVector(module, vectors);
        SimCompare.checkIverilogVector(module, vectors);
      });
    }
  }

  test('rank-zero structured fields synthesize without phantom indices',
      () async {
    final module =
        _ScalarFieldModule(TypedLogicArray<_Word, LogicValue>([], _Word.new));
    await module.build();
    final vectors = [
      Vector({'source': 13}, {'data': 5, 'flag': 1}),
      Vector({'source': 2}, {'data': 2, 'flag': 0}),
    ];
    await SimCompare.checkFunctionalVector(module, vectors);
    SimCompare.checkIverilogVector(module, vectors);
  });

  test('rank-zero array-valued leaves synthesize without an extra index',
      () async {
    final source = TypedLogicArray<LogicArray, LogicValue>(
        [], ({name}) => LogicArray([2], 3, name: name));
    final module = _ScalarModule(source, view: true);
    await module.build();
    final vectors = [
      Vector({'source': 42}, {'result': 42}),
      Vector({'source': 17}, {'result': 17}),
    ];
    await SimCompare.checkFunctionalVector(module, vectors);
    SimCompare.checkIverilogVector(module, vectors);
  });

  test('rank-zero mux and flop preserve typed storage', () async {
    final module =
        _ScalarRegister(TypedLogicArray<_Word, LogicValue>([], _Word.new));
    await module.build();
    final vectors = [
      Vector({'clk': 0, 'reset': 1, 'source': 13}, {}),
      Vector({'clk': 1}, {'result': 0}),
      Vector({'clk': 0, 'reset': 0}, {}),
      Vector({'clk': 1}, {'result': 13}),
      Vector({'clk': 0, 'source': 6}, {}),
      Vector({'clk': 1}, {'result': 6}),
    ];
    await SimCompare.checkFunctionalVector(module, vectors);
    SimCompare.checkIverilogVector(module, vectors);
  });

  test('rank-zero SystemC vectors', () async {
    final module = _ScalarModule(
        TypedLogicArray<_Word, LogicValue>([], _Word.new),
        view: true);
    await module.build();
    SimCompare.checkSystemCVector(module, [
      Vector({'source': 13}, {'result': 13}),
      Vector({'source': 2}, {'result': 2}),
    ]);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('rank-zero net port retains a typed net leaf', () async {
    final source = TypedLogicArray<LogicNet, LogicValue>(
        [], ({name}) => LogicNet(name: name, width: 4));
    final module = _ScalarNetModule(source);
    await module.build();
    final vectors = [
      Vector({'data': 13}, {'bus': 13, 'observed': 13}),
      Vector({'data': 6}, {'bus': 6, 'observed': 6}),
    ];
    await SimCompare.checkFunctionalVector(module, vectors);
    SimCompare.checkIverilogVector(module, vectors);
  });

  test('SystemC structured array regression at nonzero rank', () async {
    final module =
        _ScalarModule(TypedLogicArray<_Word, LogicValue>([2], _Word.new));
    await module.build();
    SimCompare.checkSystemCVector(module, [
      Vector({'source': 0x3d}, {'result': 0x3d}),
      Vector({'source': 0x62}, {'result': 0x62}),
    ]);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('rank-zero netlist retains empty shape and structured leaf metadata',
      () async {
    final module =
        _ScalarRegister(TypedLogicArray<_Word, LogicValue>([], _Word.new));
    await module.build();
    final json = jsonDecode(NetlistSynthesizer().synthesizeToJson(module))
        as Map<String, dynamic>;
    final modules = json['modules'] as Map<String, dynamic>;
    final definition = modules.values.cast<Map<String, dynamic>>().firstWhere(
        (definition) => (definition['ports'] as Map<String, dynamic>)
            .containsKey('source'));
    final ports = definition['ports'] as Map<String, dynamic>;
    for (final name in ['source', 'result']) {
      final port = ports[name] as Map<String, dynamic>;
      final type = port['logic_type'] as Map<String, dynamic>;
      expect(type['arrayDims'], isEmpty);
      expect(type['width'], 4);
      final leaf = type['elementType'] as Map<String, dynamic>;
      expect(leaf['fields'], hasLength(2));
    }
  });
}
