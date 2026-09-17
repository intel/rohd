// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// typed_logic_array_inout_test.dart
// Tests for typed logic array inout behavior.
//
// 2026 September 16
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class _NetMatrixCell extends LogicStructure {
  final LogicNet low;
  final LogicNet high;

  factory _NetMatrixCell({String? name}) => _NetMatrixCell._(
        LogicNet(name: 'low'),
        LogicNet(name: 'high', width: 2),
        name: name ?? 'netMatrixCell',
      );

  _NetMatrixCell._(this.low, this.high, {required String name})
      : super([low, high], name: name);

  @override
  _NetMatrixCell clone({String? name}) =>
      _NetMatrixCell(name: name ?? this.name);
}

class _ArrayValuedNetElementStructure extends LogicStructure {
  final LogicNet prefix;
  final TypedLogicArray<TypedLogicArray<_NetMatrixCell, LogicValue>, LogicValue>
      matrix;
  final LogicNet suffix;

  factory _ArrayValuedNetElementStructure({String? name}) =>
      _ArrayValuedNetElementStructure._(
        LogicNet(name: 'prefix', width: 2),
        TypedLogicArray<TypedLogicArray<_NetMatrixCell, LogicValue>,
            LogicValue>(
          [2],
          ({name}) => TypedLogicArray<_NetMatrixCell, LogicValue>(
            [3],
            _NetMatrixCell.new,
            name: name,
          ),
          name: 'matrix',
        ),
        LogicNet(name: 'suffix'),
        name: name ?? 'arrayValuedNetElement',
      );

  _ArrayValuedNetElementStructure._(
    this.prefix,
    this.matrix,
    this.suffix, {
    required String name,
  }) : super([prefix, matrix, suffix], name: name);

  @override
  _ArrayValuedNetElementStructure clone({String? name}) =>
      _ArrayValuedNetElementStructure(name: name ?? this.name);
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

class _ArrayValuedStructuredInOutDriveModule extends Module {
  late final TypedLogicArray<_ArrayValuedNetElementStructure, LogicValue> bus;

  _ArrayValuedStructuredInOutDriveModule(
      TypedLogicArray<_ArrayValuedNetElementStructure, LogicValue> source,
      Logic enable,
      Logic driveValue) {
    bus = addTypedInOut('bus', source);
    enable = addInput('enable', enable);
    driveValue = addInput('driveValue', driveValue, width: bus.width);
    final child =
        _ArrayValuedStructuredInOutDriveChild(bus, enable, driveValue);
    addOutput('observed', width: bus.width).gets(child.observed);
  }
}

class _ArrayValuedStructuredInOutDriveChild extends Module {
  late final Logic observed;

  _ArrayValuedStructuredInOutDriveChild(
      TypedLogicArray<_ArrayValuedNetElementStructure, LogicValue> source,
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

/// Checks the backends used for four-state inout resolution.
///
/// This specialized suite intentionally has narrower backend coverage than
/// the ordinary typed-array tests and does not include Verilator.
Future<void> _checkRohdAndIverilogVectors(
  Module module,
  List<Vector> vectors,
) async {
  await SimCompare.checkFunctionalVector(module, vectors);
  SimCompare.checkIverilogVector(module, vectors);
}

void _expectCompatibleNetConnectDefinition(String systemVerilog) {
  expect(
    systemVerilog,
    contains('module net_connect #(parameter int WIDTH=1) (w, w);'),
  );
  expect(systemVerilog, contains('inout wire[WIDTH-1:0] w;'));
  expect(systemVerilog, isNot(contains('tran (')));
}

List<Map<String, dynamic>> _triStateCells(
        Map<String, dynamic> moduleDefinitions) =>
    [
      for (final moduleDefinition
          in moduleDefinitions.values.cast<Map<String, dynamic>>())
        for (final cell in (moduleDefinition['cells'] as Map<String, dynamic>)
            .values
            .cast<Map<String, dynamic>>())
          if (cell['type'] == r'$tribuf') cell,
    ];

void _expectTriStateCells(
  Map<String, dynamic> moduleDefinitions, {
  required int count,
}) {
  final cells = _triStateCells(moduleDefinitions);
  expect(cells, hasLength(count));
  for (final cell in cells) {
    final directions = cell['port_directions'] as Map<String, dynamic>;
    final connections = cell['connections'] as Map<String, dynamic>;
    expect(directions['Y'], 'output');
    expect(connections['Y'] as List, isNotEmpty);
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('TypedLogicArray inout', () {
    test('drives and releases a nested structured array', () async {
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
        Vector(
          {
            'bus': LogicValue.ofInt(0, source.width),
            'enable': 1,
            'driveValue': LogicValue.ofBigInt(
              (BigInt.one << source.width) - BigInt.one,
              source.width,
            ),
          },
          {'observed': LogicValue.x},
        ),
      ];

      await _checkRohdAndIverilogVectors(module, vectors);
      final sv = module.generateSynth();
      expect(sv, contains('inout wire [1:0][8:0] bus'));
      _expectCompatibleNetConnectDefinition(sv);
      expect(source.numUnpackedDimensions, 0);
      expect(source.at([0]).lanes.numUnpackedDimensions, 1);

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
      _expectTriStateCells(
        modules,
        count: source.leafElements.length,
      );
    });

    test('resolves array-valued structured fields', () async {
      final source =
          TypedLogicArray<_ArrayValuedNetElementStructure, LogicValue>(
        [2],
        _ArrayValuedNetElementStructure.new,
      );
      final enable = Logic();
      final driveValue = Logic(width: source.width);
      final module =
          _ArrayValuedStructuredInOutDriveModule(source, enable, driveValue);
      await module.build();

      final externalValue = LogicValue.ofBigInt(
        BigInt.parse('2aa9552d5', radix: 16),
        source.width,
      );
      final internalValue = LogicValue.ofBigInt(
        BigInt.parse('1556aa5ab', radix: 16),
        source.width,
      );
      final allOnes = LogicValue.ofBigInt(
        (BigInt.one << source.width) - BigInt.one,
        source.width,
      );
      final allZeroes = LogicValue.ofBigInt(BigInt.zero, source.width);
      final vectors = [
        Vector(
          {'bus': externalValue, 'enable': 0, 'driveValue': allZeroes},
          {'observed': externalValue},
        ),
        Vector(
          {'bus': LogicValue.z, 'enable': 1, 'driveValue': internalValue},
          {'observed': internalValue},
        ),
        Vector(
          {'bus': LogicValue.z, 'enable': 0, 'driveValue': allZeroes},
          {'bus': LogicValue.z},
        ),
        Vector(
          {'bus': allZeroes, 'enable': 1, 'driveValue': allOnes},
          {'observed': LogicValue.x},
        ),
      ];

      await _checkRohdAndIverilogVectors(module, vectors);
      final sv = module.generateSynth();
      expect(sv, contains('inout wire [1:0][20:0] bus'));
      _expectCompatibleNetConnectDefinition(sv);

      final netlist = jsonDecode(
        NetlistSynthesizer().synthesizeToJson(module),
      ) as Map<String, dynamic>;
      final modules = netlist['modules'] as Map<String, dynamic>;
      final top = modules['_ArrayValuedStructuredInOutDriveModule']
          as Map<String, dynamic>;
      final ports = top['ports'] as Map<String, dynamic>;
      final busPort = ports['bus'] as Map<String, dynamic>;
      final busType = busPort['logic_type'] as Map<String, dynamic>;
      final elementType = busType['elementType'] as Map<String, dynamic>;
      final fields =
          (elementType['fields'] as List).cast<Map<String, dynamic>>();
      final matrixType = fields.singleWhere(
        (field) => field['name'] == 'matrix',
      )['type'] as Map<String, dynamic>;
      final matrixElementType =
          matrixType['elementType'] as Map<String, dynamic>;
      expect(busPort['direction'], 'inout');
      expect(busPort['bits'], hasLength(source.width));
      expect(busType['arrayDims'], [2]);
      expect(matrixType['arrayDims'], [2]);
      expect(matrixElementType['arrayDims'], [3]);
      _expectTriStateCells(
        modules,
        count: source.leafElements.length,
      );
    });
  });
}
