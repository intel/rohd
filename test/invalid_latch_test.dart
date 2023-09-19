// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// invalid_latch_test.dart
// Test behavior when latch-like logic is constructed at a gate level.
//
// 2023 April 17
// Based on bug reports:
// - https://github.com/intel/rohd/issues/286
// - https://github.com/intel/rohd/issues/285

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

/// A two-input NAND gate.
class _Nand2Gate extends Module {
  /// Calculates the NAND of `in0` and `in1`.
  _Nand2Gate(Logic in0, Logic in1) {
    in0 = addInput(in0.name, in0);
    in1 = addInput(in1.name, in1);

    _out.gets(NotGate(And2Gate(in0, in1).out).out);
  }

  /// The output of this gate.
  Logic get out => output(_out.name);

  late final _out = addOutput(Logic().name);
}

enum _DLatchCombType { assignments, oneComb, manyCombs }

/// Represents a single D-Latch with no reset.
class _DLatch extends Module {
  /// Constructs a D-Latch.
  _DLatch(Logic en, Logic d, _DLatchCombType combType) {
    en = addInput('en', en);
    d = addInput('d', d);

    final nand2gate0 = _Nand2Gate(en, d);
    final nand2gate1 = _Nand2Gate(en, nand2gate0.out);
    final nand2gate2 = _Nand2Gate(nand2gate0.out, _outB);
    final nand2gate3 = _Nand2Gate(nand2gate1.out, _out);

    switch (combType) {
      case _DLatchCombType.assignments:
        _out.gets(nand2gate2.out);
        _outB.gets(nand2gate3.out);
        break;
      case _DLatchCombType.oneComb:
        Combinational([
          ConditionalAssign(_out, nand2gate2.out),
          ConditionalAssign(_outB, nand2gate3.out)
        ]);
        break;
      case _DLatchCombType.manyCombs:
        Combinational([ConditionalAssign(_out, nand2gate2.out)]);
        Combinational([ConditionalAssign(_outB, nand2gate3.out)]);
        break;
    }
  }

  /// The direct output of the latch.
  Logic get out => output(_out.name);

  /// The inverse output of the latch.
  Logic get outB => output(_outB.name);

  late final _out = addOutput('out');
  late final _outB = addOutput('outB');
}

void main() async {
  setUp(() async {
    await Simulator.reset();
  });

  group('dLatch', () {
    for (final combType in _DLatchCombType.values) {
      group(combType.name, () {
        Future<void> runVectors(
            List<Map<String, dynamic>> vectorStimulus) async {
          // either expect the outputs to be X all the time, or an exception
          final vectors = vectorStimulus
              .map(
                  (e) => Vector(e, {'out': LogicValue.x, 'outB': LogicValue.x}))
              .toList();

          try {
            final dLatch = _DLatch(Logic(), Logic(), combType);
            await dLatch.build();
            await SimCompare.checkFunctionalVector(dLatch, vectors);
          } on Exception catch (e) {
            expect(e.runtimeType, WriteAfterReadException);
          }
        }

        test('en = 0, out is blocked', () async {
          await runVectors([
            {'en': 0, 'd': 0},
            {'en': 0, 'd': 1},
          ]);
        });

        test('en = 1, passthrough is blocked', () async {
          await runVectors([
            {'en': 1, 'd': 0},
            {'en': 1, 'd': 1},
          ]);
        });

        test('en 1->0, value latch is blocked', () async {
          await runVectors([
            {'en': 0, 'd': 0},
            {'en': 1, 'd': 1},
            {'en': 0, 'd': 0},
          ]);
        });
      });
    }
  });
}
