// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// slim_full_canonical_test.dart
// Validates that slim and full synthesis produce identical cell sets.

import 'dart:convert';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

import '../example/filter_bank.dart';

void main() {
  tearDown(() async {
    await Simulator.reset();
    ModuleServices.instance.reset();
  });

  test('slim and full produce identical cell keys for FilterBank', () async {
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

    // 1. Get slim JSON
    final slimJsonStr = netSvc.slimJson;

    final slimUnified = jsonDecode(slimJsonStr) as Map<String, dynamic>;
    final slimNetlist = slimUnified['netlist'] as Map<String, dynamic>;
    final slimModules = slimNetlist['modules'] as Map<String, dynamic>;

    expect(slimModules, isNotEmpty, reason: 'No slim modules found');

    // 2. For each slim module, fetch full and compare cell keys
    var modulesTested = 0;
    final mismatches = <String>[];

    for (final moduleKey in slimModules.keys) {
      final slimMod = slimModules[moduleKey] as Map<String, dynamic>;
      final slimCells = slimMod['cells'] as Map<String, dynamic>? ?? {};

      // Fetch full data
      final fullJsonStr = netSvc.moduleJson(moduleKey);
      final fullJson = jsonDecode(fullJsonStr) as Map<String, dynamic>;
      if (fullJson.containsKey('status')) {
        mismatches.add('$moduleKey: full fetch returned not_found');
        continue;
      }

      // moduleJson returns {creator, version, modules: {name: modData}}.
      final modulesMap =
          (fullJson['modules'] as Map<String, dynamic>?) ?? fullJson;
      final fullMod = modulesMap[moduleKey] as Map<String, dynamic>?;
      if (fullMod == null) {
        // Try the first key in case the definition name differs.
        final firstKey = modulesMap.keys.first;
        final altMod = modulesMap[firstKey] as Map<String, dynamic>?;
        if (altMod == null) {
          mismatches.add('$moduleKey: no module data in full response');
          continue;
        }
        _compareCells(moduleKey, slimCells, altMod, mismatches);
      } else {
        _compareCells(moduleKey, slimCells, fullMod, mismatches);
      }
      modulesTested++;
    }

    // Report
    if (mismatches.isNotEmpty) {
      fail(
        'Cell key mismatches found in $modulesTested modules:\n'
        '${mismatches.join('\n')}',
      );
    }

    // Sanity: we tested a reasonable number of modules
    expect(modulesTested, greaterThan(0), reason: 'No modules were tested');
  });
}

void _compareCells(
  String moduleKey,
  Map<String, dynamic> slimCells,
  Map<String, dynamic> fullMod,
  List<String> mismatches,
) {
  final fullCells = fullMod['cells'] as Map<String, dynamic>? ?? {};

  final slimKeys = slimCells.keys.toList();
  final fullKeys = fullCells.keys.toList();

  if (slimKeys.length != fullKeys.length) {
    mismatches.add(
      '$moduleKey: cell count differs — '
      'slim=${slimKeys.length}, full=${fullKeys.length}',
    );
    // Show which keys differ
    final slimOnly = slimKeys.toSet().difference(fullKeys.toSet());
    final fullOnly = fullKeys.toSet().difference(slimKeys.toSet());
    if (slimOnly.isNotEmpty) {
      mismatches.add('  slim-only: $slimOnly');
    }
    if (fullOnly.isNotEmpty) {
      mismatches.add('  full-only: $fullOnly');
    }
    return;
  }

  // Check ordering matches
  for (var i = 0; i < slimKeys.length; i++) {
    if (slimKeys[i] != fullKeys[i]) {
      mismatches.add(
        '$moduleKey: cell key ordering differs at index $i — '
        'slim="${slimKeys[i]}", full="${fullKeys[i]}"',
      );
      return;
    }
  }

  // Check cell types match
  for (final key in slimKeys) {
    final slimCell = slimCells[key] as Map<String, dynamic>;
    final fullCell = fullCells[key] as Map<String, dynamic>;
    final slimType = slimCell['type'] as String?;
    final fullType = fullCell['type'] as String?;
    if (slimType != fullType) {
      mismatches.add(
        '$moduleKey: cell "$key" type differs — '
        'slim="$slimType", full="$fullType"',
      );
    }
  }

  // Verify slim cells DON'T have connections
  for (final key in slimKeys) {
    final slimCell = slimCells[key] as Map<String, dynamic>;
    if (slimCell.containsKey('connections')) {
      mismatches.add(
        '$moduleKey: slim cell "$key" has connections '
        '(should be stripped)',
      );
    }
  }

  // Verify full cells DO have connections
  for (final key in fullKeys) {
    final fullCell = fullCells[key] as Map<String, dynamic>;
    if (!fullCell.containsKey('connections')) {
      mismatches.add('$moduleKey: full cell "$key" missing connections');
    }
  }
}
