/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// tree_test.dart
/// Testing a recursive tree of arbitrary two input operations, based on a Chisel example
///
/// 2021 May 20
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';
import 'package:rohd/src/utilities/simcompare.dart';

class TreeOfTwoInputModules extends Module {
  final Logic Function(Logic a, Logic b) _op;
  final List<Logic> _seq = [];
  Logic get out => output('out');

  TreeOfTwoInputModules(List<Logic> seq, this._op)
      : super(name: 'tree_of_two_input_modules') {
    if (seq.isEmpty) {
      throw Exception("Don't use TreeOfTwoInputModules with an empty sequence");
    }

    for (var i = 0; i < seq.length; i++) {
      _seq.add(addInput('seq$i', seq[i], width: seq[i].width));
    }
    addOutput('out', width: seq[0].width);

    if (_seq.length == 1) {
      out <= _seq[0];
    } else {
      var a = TreeOfTwoInputModules(
              _seq.getRange(0, _seq.length ~/ 2).toList(), _op)
          .out;
      var b = TreeOfTwoInputModules(
              _seq.getRange(_seq.length ~/ 2, _seq.length).toList(), _op)
          .out;
      out <= _op(a, b);
    }
  }
}

void main() {
  // var mod = TreeOfTwoInputModules(
  //   List<Logic>.generate(16, (index) => Logic(width: 8)),
  //   (Logic a, Logic b) => Mux(a > b, a, b).y
  // );
  // mod.build();
  // File('tmp_tree.sv').writeAsStringSync(mod.generateSynth());

  tearDown(() {
    Simulator.reset();
  });

  group('simcompare', () {
    test('tree', () async {
      var mod = TreeOfTwoInputModules(
          List<Logic>.generate(16, (index) => Logic(width: 8)),
          (Logic a, Logic b) => Mux(a > b, a, b).y);
      await mod.build();
      // File('tmp_tree.sv').writeAsStringSync(mod.generateSynth());

      var vectors = [
        Vector({
          for (var i in List<int>.generate(16, (index) => index)) 'seq$i': i
        }, {
          'out': 15
        }),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      var simResult = SimCompare.iverilogVector(
          mod.generateSynth(), mod.runtimeType.toString() + '_3', vectors,
          signalToWidthMap: {
            ...{
              for (var i in List<int>.generate(16, (index) => index)) 'seq$i': 8
            },
            'out': 8
          });
      expect(simResult, equals(true));
    });
  });
}
