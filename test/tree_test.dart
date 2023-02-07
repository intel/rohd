/// Copyright (C) 2021-2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// tree_test.dart
/// Testing a recursive tree of arbitrary two input operations,
/// based on a Chisel example
///
/// 2021 May 20
/// Author: Max Korbel <max.korbel@intel.com>
///
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

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
      final a = TreeOfTwoInputModules(
              _seq.getRange(0, _seq.length ~/ 2).toList(), _op)
          .out;
      final b = TreeOfTwoInputModules(
              _seq.getRange(_seq.length ~/ 2, _seq.length).toList(), _op)
          .out;
      out <= _op(a, b);
    }
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('simcompare', () {
    test('tree', () async {
      final mod = TreeOfTwoInputModules(
          List<Logic>.generate(16, (index) => Logic(width: 8)),
          (a, b) => mux(a > b, a, b));
      await mod.build();
      // File('tmp_tree.sv').writeAsStringSync(mod.generateSynth());

      final vectors = [
        Vector({
          for (var i in List<int>.generate(16, (index) => index)) 'seq$i': i
        }, {
          'out': 15
        }),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors,
          moduleName: '${mod.runtimeType}_3');
      expect(simResult, equals(true));
    });
  });
}
