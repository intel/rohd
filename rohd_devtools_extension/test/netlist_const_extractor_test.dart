// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// netlist_const_extractor_test.dart
// Tests for netlist constant extraction.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/netlist_const_extractor.dart';

import '../../example/filter_bank/filter_bank_modules.dart';

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
      consts.containsKey('FilterBank/ch0/coeffArray_0_'),
      isTrue,
      reason: 'ch0/coeffArray_0 should be extracted',
    );
    expect(
      consts.containsKey('FilterBank/ch0/coeffArray_1_'),
      isTrue,
      reason: 'ch0/coeffArray_1 should be extracted',
    );
    expect(
      consts.containsKey('FilterBank/ch0/coeffArray_2_'),
      isTrue,
      reason: 'ch0/coeffArray_2 should be extracted',
    );

    // Check values: ch0 coefficients = [1, 2, 1]
    expect(consts['FilterBank/ch0/coeffArray_0_']!['value'], "16'h1");
    expect(consts['FilterBank/ch0/coeffArray_1_']!['value'], "16'h2");
    expect(consts['FilterBank/ch0/coeffArray_2_']!['value'], "16'h1");

    // Check values: ch1 coefficients = [1, -2 (0xFFFE), 1]
    expect(consts['FilterBank/ch1/coeffArray_0_']!['value'], "16'h1");
    expect(consts['FilterBank/ch1/coeffArray_1_']!['value'], "16'hfffe");
    expect(consts['FilterBank/ch1/coeffArray_2_']!['value'], "16'h1");
  });
}
