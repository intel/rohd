// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_data_service_test.dart
// Tests for the in-memory DevTools waveform data service.
//
// 2026 November 6
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class _WaveformDataServiceModule extends Module {
  _WaveformDataServiceModule(Logic data) {
    data = addInput('data', data);
    addOutput('result') <= ~data;
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
    WaveformDataService.instance.clear();
  });

  test('initializes and records waveform data without VM extensions', () async {
    final input = Logic(name: 'input');
    final module = _WaveformDataServiceModule(input);
    await module.build();

    WaveformDataService.init(module);
    expect(WaveformDataService.instance.startRecording(), isTrue);

    input.inject(1);
    await Simulator.tick();

    final snapshot = jsonDecode(
      WaveformDataService.instance.getSnapshotJSON(Simulator.time),
    ) as Map<String, dynamic>;
    expect(WaveformDataService.instance.isInitialized, isTrue);
    expect(snapshot['signals'], isNotEmpty);
  });
}
