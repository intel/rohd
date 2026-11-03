// Copyright (C) 2021-2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// example_test.dart
// Tests to make sure that the examples don't break.
//
// 2021 September 17
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

import '../example/example.dart' as counter;
import '../example/fir_filter.dart' as fir_filter;
import '../example/logic_array.dart' as logic_array;
import '../example/oven_fsm.dart' as fsm;
import '../example/tree.dart' as tree;

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('counter example', () async {
    await counter.main(noPrint: true);
  });

  test('tree example', () async {
    await tree.main(noPrint: true);
  });

  test('fir filter example', () async {
    await fir_filter.main(noPrint: true);
  });

  test('fsm example', () async {
    await fsm.main(noPrint: true);
  });

  test('fsm example uses enum mappings for buttons and LEDs', () async {
    final button = LogicEnum<fsm.Button>.withMapping({
      fsm.Button.start: 1,
      fsm.Button.pause: 4,
      fsm.Button.resume: 6,
    });
    final oven = fsm.OvenModule(button, Logic(), Logic());
    await oven.build();
    expect((oven.input('button') as LogicEnum<fsm.Button>).mapping,
        button.mapping);
    expect(button.width, 3);
    expect(oven.led.width, 4);
    expect(
        oven.led.mapping
            .map((light, encoding) => MapEntry(light, encoding.toInt())),
        {
          fsm.LedLight.yellow: 1,
          fsm.LedLight.blue: 2,
          fsm.LedLight.red: 4,
          fsm.LedLight.green: 8,
        });

    final vectors = <Vector>[];
    for (final (pressed, reset, light) in [
      (fsm.Button.pause, 1, fsm.LedLight.blue),
      (fsm.Button.pause, 1, fsm.LedLight.blue),
      (fsm.Button.start, 0, fsm.LedLight.yellow),
      (fsm.Button.pause, 0, fsm.LedLight.red),
      (fsm.Button.pause, 0, fsm.LedLight.red),
      (fsm.Button.resume, 0, fsm.LedLight.yellow),
      (fsm.Button.resume, 0, fsm.LedLight.yellow),
      (fsm.Button.resume, 0, fsm.LedLight.yellow),
      (fsm.Button.resume, 0, fsm.LedLight.yellow),
      (fsm.Button.resume, 0, fsm.LedLight.green),
      (fsm.Button.resume, 0, fsm.LedLight.green),
      (fsm.Button.start, 0, fsm.LedLight.yellow),
    ]) {
      vectors
        ..add(Vector(
            {'button': button.mapping[pressed], 'reset': reset, 'clk': 0}, {}))
        ..add(Vector({'clk': 1}, {'led': oven.led.mapping[light]}));
    }
    await SimCompare.checkFunctionalVector(oven, vectors);
    expect(oven.led.valueEnum, fsm.LedLight.yellow);
    for (final generateEnums in [true, false]) {
      final configuration =
          SystemVerilogSynthesizerConfiguration(generateEnums: generateEnums);
      SimCompare.checkIverilogVector(oven, vectors,
          synthesizerConfiguration: configuration);
      SimCompare.checkVerilatorVector(oven, const [],
          buildOnly: true, synthesizerConfiguration: configuration);
    }
  });

  test('logic array example', () async {
    await logic_array.main(noPrint: true);
  });
}
