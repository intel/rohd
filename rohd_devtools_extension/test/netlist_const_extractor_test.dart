// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// netlist_const_extractor_test.dart
// Tests for netlist constant extraction.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd/examples.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/netlist_const_extractor.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/netlist_evaluator.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_schematic_viewer/schematic_connectivity.dart'
    show NetlistSchematicConnectivity;

void main() {
  tearDown(() async {
    await Simulator.reset();
    ModuleServices.instance.reset();
  });

  test('extracts coefficient constants correctly', () async {
    final clk = SimpleClockGenerator(10).clk;
    final reset = Logic(name: 'reset');
    final start = Logic(name: 'start');
    final samples = List.generate(2, (ch) => FilterSample(name: 'sample$ch'));
    final inputDone = Logic(name: 'inputDone');

    final dut = FilterBank(
      clk,
      reset,
      start,
      samples,
      inputDone,
      numTaps: 3,
      dataWidth: 16,
      coefficients: [
        [1, 2, 1],
        [1, -2, 1],
      ],
    );
    await dut.build();
    final netSvc = NetlistService(dut);

    final json = jsonDecode(netSvc.json) as Map<String, dynamic>;
    final consts = NetlistConstExtractor.extract(json, 'FilterBank');

    // Print all coefficient-related constants for debugging
    for (final e in consts.entries) {
      if (e.key.contains('coeff')) {
        // Values are emitted only to aid diagnosis when this assertion fails.
        // ignore: avoid_print
        print('${e.key}: ${e.value}');
      }
    }

    // Sub-signals should have correct individual values for ch0
    expect(
      consts.containsKey('FilterBank/ch0/coeffArray[0]'),
      isTrue,
      reason: 'ch0/coeffArray[0] should be extracted',
    );
    expect(
      consts.containsKey('FilterBank/ch0/coeffArray[1]'),
      isTrue,
      reason: 'ch0/coeffArray[1] should be extracted',
    );
    expect(
      consts.containsKey('FilterBank/ch0/coeffArray[2]'),
      isTrue,
      reason: 'ch0/coeffArray[2] should be extracted',
    );

    // Check values: ch0 coefficients = [1, 2, 1]
    expect(consts['FilterBank/ch0/coeffArray[0]']!['value'], "16'h1");
    expect(consts['FilterBank/ch0/coeffArray[1]']!['value'], "16'h2");
    expect(consts['FilterBank/ch0/coeffArray[2]']!['value'], "16'h1");

    // Check values: ch1 coefficients = [1, -2 (0xFFFE), 1]
    expect(consts['FilterBank/ch1/coeffArray[0]']!['value'], "16'h1");
    expect(consts['FilterBank/ch1/coeffArray[1]']!['value'], "16'hfffe");
    expect(consts['FilterBank/ch1/coeffArray[2]']!['value'], "16'h1");

    final hierarchy =
        NetlistHierarchyAdapter.fromMap(json, rootNameOverride: 'FilterBank');
    final evaluator = NetlistEvaluator(json['modules'] as Map<String, dynamic>);
    final schematic = NetlistSchematicConnectivity.fromJson(
      netSvc.json,
      externalHierarchy: hierarchy,
    );
    final bank = hierarchy.occurrenceByPathname('FilterBank/ch0/coeffBank')!;
    final constants =
        bank.children.where((cell) => cell.definition == r'$const').toList();
    expect(constants, isNotEmpty);
    for (final cell in constants) {
      final port = cell.ports.single;
      expect(hierarchy.occurrenceByPathname(cell.path()), same(cell));
      expect(hierarchy.portByPathname(port.path()), same(port));
      expect(evaluator.canEvaluate(port.path()), isTrue);
      expect(evaluator.isComputed(port.path()), isTrue);
      expect(evaluator.signalWidth(port.path()), port.width);
      expect(evaluator.evaluate(cell.path(), (_) => null), (
        value: LogicValue.ofRadixString(port.name).toString(),
        width: port.width
      ));
      expect(
        evaluator.evaluateBatch([port.path()], (_) => null)[port.path()],
        LogicValue.ofRadixString(port.name),
      );

      final wireName = cell.name.replaceFirst(RegExp(r'_driver$'), '');
      final wire =
          bank.signals.singleWhere((signal) => signal.name == wireName);
      expect(evaluator.evaluate(wire.path(), (_) => null)?.value,
          LogicValue.ofRadixString(port.name).toString());
      expect(
        schematic.fanin(wire).map((endpoint) => endpoint.nodeAddress),
        contains(cell.address),
      );
    }
  });
}
