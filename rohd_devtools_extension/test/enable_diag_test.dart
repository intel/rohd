// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// enable_diag_test.dart
// Diagnostic: find why `enable` has no waveform data.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd/rohd.dart' show WaveformDataService;
import 'package:rohd_devtools_extension/rohd_devtools/examples/rohd_examples.dart';

void main() {
  test('enable signal diagnostic', () async {
    // Launch FilterBank+InOut example.
    final examples = rohdExamples.where((e) => e.name == 'FilterBank').toList();
    expect(examples, hasLength(1));
    final example = examples.first;
    final keepAlive = await example.launcher();
    keepAlive.complete();

    final ws = WaveformDataService.instance;
    final signalData = ws.debugGetSignalData();
    final signalLogicMap = ws.debugGetSignalLogicMap();

    // Print summary counts.
    // ignore: avoid_print
    print('Total metadata: ${ws.signalCount}');
    // Console output makes this diagnostic test useful when run manually.
    // ignore: avoid_print
    print('Total tracked (in signalData): ${signalData.length}');

    // Find all signals with 'enable' in the path.
    final allMeta = <String>[];
    final enableTracked = <String>[];
    final enableHasLogic = <String>[];

    // We need to access _signalMetadata, but debugGetSignalData only exposes
    // _signalData. Let's check both maps.
    for (final path in signalData.keys) {
      allMeta.add(path);
      if (path.toLowerCase().contains('enable')) {
        enableTracked.add(path);
      }
    }

    for (final path in signalLogicMap.keys) {
      if (path.toLowerCase().contains('enable')) {
        enableHasLogic.add(path);
      }
    }

    // Console output exposes which expected signals were actually tracked.
    // ignore: avoid_print
    print('\n=== TRACKED signals containing "enable" ===');
    for (final p in enableTracked) {
      final changes = signalData[p]?.length ?? 0;
      // Each signal's transition count is the diagnostic payload.
      // ignore: avoid_print
      print('  $p  ($changes changes)');
    }

    // Console output separates the Logic-reference diagnostic section.
    // ignore: avoid_print
    print('\n=== Signals with Logic ref containing "enable" ===');
    for (final p in enableHasLogic) {
      final inData = signalData.containsKey(p);
      // Each signal's tracking status is the diagnostic payload.
      // ignore: avoid_print
      print('  $p  tracked=$inData');
    }

    // Show all tracked signals to see which are present
    // ignore: avoid_print
    print('\n=== ALL tracked signals (${signalData.length}) ===');
    final sortedPaths = signalData.keys.toList()..sort();
    for (final p in sortedPaths) {
      // Listing every path helps diagnose unexpectedly missing signals.
      // ignore: avoid_print
      print('  $p  (${signalData[p]!.length} changes)');
    }
  });
}
