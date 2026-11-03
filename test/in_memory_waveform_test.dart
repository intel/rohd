// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// in_memory_waveform_test.dart
// Tests VCD waveform capture without filesystem output.
//
// 2026 November
// Author: Desmond Kirkpatrick <desmond.kirkpatrick@intel.com>

import 'dart:convert';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class _InMemoryWaveformModule extends Module {
  _InMemoryWaveformModule(Logic data) {
    data = addInput('data', data);
    addOutput('out') <= data;
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
    ModuleServices.instance.reset();
  });

  test('retains VCD output without filesystem writes', () async {
    final data = Logic(name: 'data');
    final module = _InMemoryWaveformModule(data);
    await module.build();

    final waveform = WaveformService(
      module,
      register: false,
    );

    data.inject(1);
    Simulator.registerAction(10, () => data.put(0));
    await Simulator.run();

    final output = waveform.inMemoryOutput;
    expect(output, isNotNull);
    expect(output, contains(r'$enddefinitions $end'));
    expect(output, contains('#10'));

    final artifact = waveform.artifacts.single;
    final artifactOutput = await utf8.decoder.bind(artifact.openRead()).join();
    expect(artifactOutput, equals(output));
  });
}
