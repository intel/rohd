/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
/// 
/// counter_test.dart
/// Unit tests for a basic counter
/// 
/// 2021 May 10
/// Author: Max Korbel <max.korbel@intel.com>
/// 

import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';
import 'package:rohd/src/utilities/simcompare.dart';


class Counter extends Module {
  final int width;
  Counter(Logic en, Logic reset, {this.width=8}) : super(name: 'counter') {
    en = addInput('en', en);
    reset = addInput('reset', reset);

    var val = addOutput('val', width: width);

    var nextVal = Logic(name: 'nextVal', width: width);
    
    nextVal <= val + 1;

    FF( (SimpleClockGenerator(10).clk), [
      If(reset, then:[
        val < 0
      ], orElse: [If(en, then: [
        val < nextVal
      ])])
    ]);
  }
}


void main() {
  
  tearDown(() {
    Simulator.reset();
  });

  group('simcompare', () {

    test('counter', () async {
      var mod = Counter(Logic(), Logic());
      await mod.build();
      // File('tmp_counter.sv').writeAsStringSync(mod.generateSynth());
      var vectors = [
        Vector({'en': 0, 'reset': 1}, {}),
        Vector({'en': 0, 'reset': 1}, {'val': 0}),
        Vector({'en': 1, 'reset': 1}, {'val': 0}),
        Vector({'en': 1, 'reset': 0}, {'val': 0}),
        Vector({'en': 1, 'reset': 0}, {'val': 1}),
        Vector({'en': 1, 'reset': 0}, {'val': 2}),
        Vector({'en': 1, 'reset': 0}, {'val': 3}),
        Vector({'en': 0, 'reset': 0}, {'val': 4}),
        Vector({'en': 0, 'reset': 0}, {'val': 4}),
        Vector({'en': 1, 'reset': 0}, {'val': 4}),
        Vector({'en': 0, 'reset': 0}, {'val': 5}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      var simResult = SimCompare.iverilogVector(mod.generateSynth(), mod.runtimeType.toString(), vectors,
        signalToWidthMap: {'val':8}
      );
      expect(simResult, equals(true));
    });


  });
}

