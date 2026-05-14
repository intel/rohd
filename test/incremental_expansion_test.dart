// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// incremental_expansion_test.dart
// Tests for the incremental expansion protocol:
// - original_signal_count / original_cell_count attributes in slim JSON
// - HierarchyNode.extendSignals / extendChildren

import 'dart:convert';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/examples/filter_bank_modules.dart';
import 'package:test/test.dart';

import '../example/example.dart' as ex;
import '../example/filter_bank.dart';

void main() {
  tearDown(() async {
    await Simulator.reset();
    ModuleServices.instance.reset();
  });

  // ─────── original_signal_count / original_cell_count ────────────────

  group('original_signal_count / original_cell_count', () {
    test('Counter slim JSON has counts in attributes', () async {
      final en = Logic(name: 'en');
      final reset = Logic(name: 'reset');
      final clk = SimpleClockGenerator(10).clk;
      final counter = ex.Counter(en, reset, clk);
      await counter.build();
      final netSvc = await NetlistService.create(counter);

      final slimStr = netSvc.slimJson;
      final unified = jsonDecode(slimStr) as Map<String, dynamic>;
      final netlist = unified['netlist'] as Map<String, dynamic>;
      final modules = netlist['modules'] as Map<String, dynamic>;

      for (final entry in modules.entries) {
        final mod = entry.value as Map<String, dynamic>;
        final attrs = mod['attributes'] as Map<String, dynamic>;
        expect(
          attrs.containsKey('original_signal_count'),
          isTrue,
          reason: '${entry.key} missing original_signal_count',
        );
        expect(
          attrs.containsKey('original_cell_count'),
          isTrue,
          reason: '${entry.key} missing original_cell_count',
        );

        final sigCount = attrs['original_signal_count'] as int;
        final cellCount = attrs['original_cell_count'] as int;
        final netnames = mod['netnames'] as Map<String, dynamic>? ?? {};
        final cells = mod['cells'] as Map<String, dynamic>? ?? {};

        // Counts must match the actual number of entries in slim JSON.
        expect(
          sigCount,
          equals(netnames.length),
          reason: '${entry.key}: original_signal_count mismatch',
        );
        expect(
          cellCount,
          equals(cells.length),
          reason: '${entry.key}: original_cell_count mismatch',
        );
      }
    });

    test('FilterBank slim JSON has counts in attributes', () async {
      final clk = SimpleClockGenerator(10).clk;
      final reset = Logic(name: 'reset');
      final start = Logic(name: 'start');
      final samples = List.generate(2, (ch) => FilterSample(name: 'sample$ch'));
      final inputDone = Logic(name: 'inputDone');
      final filterBank = FilterBank(
        clk,
        reset,
        start,
        samples,
        inputDone,
        numTaps: 4,
        dataWidth: 16,
        coefficients: [List.filled(4, 1), List.filled(4, 1)],
      );
      await filterBank.build();
      final netSvc = await NetlistService.create(filterBank);

      final slimStr = netSvc.slimJson;
      final unified = jsonDecode(slimStr) as Map<String, dynamic>;
      final netlist = unified['netlist'] as Map<String, dynamic>;
      final modules = netlist['modules'] as Map<String, dynamic>;

      // At least the root module should have counts.
      expect(modules.isNotEmpty, isTrue);
      for (final entry in modules.entries) {
        final mod = entry.value as Map<String, dynamic>;
        final attrs = mod['attributes'] as Map<String, dynamic>;
        expect(
          attrs['original_signal_count'],
          isA<int>(),
          reason: '${entry.key}: original_signal_count not int',
        );
        expect(
          attrs['original_cell_count'],
          isA<int>(),
          reason: '${entry.key}: original_cell_count not int',
        );
      }
    });
  });
}
