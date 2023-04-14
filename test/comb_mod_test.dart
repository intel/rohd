/// Copyright (C) 2021-2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// comb_mod_test.dart
/// Unit tests related to Combinationals and other Modules.
///
/// 2022 September 26
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:rohd/src/exceptions/conditionals/write_after_read_exception.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class IncrModule extends Module {
  Logic get result => output('result');
  IncrModule(Logic toIncr) {
    toIncr = addInput('toIncr', toIncr, width: toIncr.width);
    addOutput('result', width: toIncr.width);
    result <= toIncr + 1;
  }
}

class ReuseExample extends Module {
  ReuseExample(Logic a) {
    a = addInput('a', a, width: a.width);
    final b = addOutput('b', width: a.width);

    final intermediate = Logic(name: 'intermediate', width: a.width);

    final inc = IncrModule(intermediate);

    Combinational([
      intermediate < a,
      intermediate < inc.result,
      intermediate < inc.result,
    ]);

    b <= intermediate;
  }
}

class ReuseExampleSsa extends Module {
  ReuseExampleSsa(Logic a) {
    a = addInput('a', a, width: a.width);
    final b = addOutput('b', width: a.width);

    final intermediate = Logic(name: 'intermediate', width: a.width);

    final inc = IncrModule(intermediate);

    Combinational.ssa((s) => [
          s(intermediate) < a,
          s(intermediate) < inc.result,
          s(intermediate) < inc.result,
        ]);

    b <= intermediate;
  }
}

class DuplicateExample extends Module {
  DuplicateExample(Logic a) {
    a = addInput('a', a, width: a.width);
    final b = addOutput('b', width: a.width);

    final intermediate = Logic(name: 'intermediate', width: a.width);

    Combinational([
      intermediate < a,
      intermediate < IncrModule(intermediate).result,
      intermediate < IncrModule(intermediate).result,
    ]);

    b <= intermediate;
  }
}

class DuplicateExampleSsa extends Module {
  DuplicateExampleSsa(Logic a) {
    a = addInput('a', a, width: a.width);
    final b = addOutput('b', width: a.width);

    final intermediate = Logic(name: 'intermediate', width: a.width);

    Combinational.ssa((s) => [
          s(intermediate) < a,
          s(intermediate) < IncrModule(s(intermediate)).result,
          s(intermediate) < IncrModule(s(intermediate)).result,
        ]);

    b <= intermediate;
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('module reuse', () {
    test('should fail normally', () async {
      try {
        final mod = ReuseExample(Logic(width: 8));
        await mod.build();

        final vectors = [
          Vector({'a': 3}, {'b': 5}) // apply twice (SV behavior)
        ];

        await SimCompare.checkFunctionalVector(mod, vectors);

        fail('Expected to throw an exception!');
      } on Exception catch (e) {
        expect(e.runtimeType, WriteAfterReadException);
      }
    });

    test('should generate X with combo loop with ssa', () async {
      final mod = ReuseExampleSsa(Logic(width: 8));
      await mod.build();

      final vectors = [
        Vector({'a': 3}, {'b': LogicValue.x})
      ];

      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });
  });

  group('module duplicate assignment', () {
    final vectors = [
      Vector({'a': 3}, {'b': 5})
    ];

    test('should fail normally', () async {
      try {
        final mod = DuplicateExample(Logic(width: 8));
        await mod.build();

        await SimCompare.checkFunctionalVector(mod, vectors);

        fail('Expected to throw an exception!');
      } on Exception catch (e) {
        expect(e.runtimeType, WriteAfterReadException);
      }
    });

    test('should apply twice with ssa', () async {
      final mod = DuplicateExampleSsa(Logic(width: 8));
      await mod.build();

      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors);
      expect(simResult, equals(true));
    });
  });
}
