// Copyright (C) 2022-2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_name_test.dart
// Unit tests for logic name initialization
//
// 2022 October 26
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/sanitizer.dart';
import 'package:test/test.dart';

class LogicTestModule extends Module {
  LogicTestModule(String logicName) {
    addInput(logicName, Logic());
  }
}

class LogicWithInternalSignalModule extends Module {
  LogicWithInternalSignalModule(Logic i) {
    i = addInput('i', i);

    final o = addOutput('o');

    // this `put` should *not* impact the name of x
    final x = Logic(name: 'shouldExist')..put(1);

    o <= i & x;
  }
}

class ParentMod extends Module {
  ParentMod(Logic clk, Logic a) {
    clk = addInput('clk', clk);
    addInput('a', a);

    final otherA = Logic();
    ChildMod(clk, otherA);
  }
}

class ChildMod extends Module {
  ChildMod(Logic clk, Logic a) {
    addInput('clk', clk);
    addInput('a', a);
  }
}

void main() {
  test(
      'GIVEN logic name is valid '
      'THEN expected to see proper name being generated', () async {
    final bus = Logic(name: 'validName');
    expect(bus.name, equals('validName'));
  });

  test('Test signals for sanitized names', () async {
    expect(Sanitizer.isSanitary(Const(LogicValue.ofString('1x0101z')).name),
        isTrue);
  });

  test('GIVEN logic name is invalid THEN expected to see sanitized name',
      () async {
    final bus = Logic(name: '&*-FinvalidN11Me');
    expect(bus.name, equals('___FinvalidN11Me'));
  });

  test('GIVEN logic name is null THEN expected to see autogeneration of name',
      () async {
    final bus = Logic();
    expect(bus.name, equals('s0'));
  });

  test(
      'GIVEN logic name is empty string THEN expected to see autogeneration '
      'of name', () async {
    final bus = Logic(name: '');
    expect(bus.name, isNot(equals('')));
  });

  group('port name:', () {
    test('GIVEN port name is empty string THEN expected to see exception',
        () async {
      expect(() async {
        LogicTestModule('');
      }, throwsA((dynamic e) => e is InvalidPortNameException));
    });
  });

  test(
      'non-synthesizable signal deposition should not impact generated verilog',
      () async {
    final mod = LogicWithInternalSignalModule(Logic());
    await mod.build();

    expect(mod.generateSynth(), contains('shouldExist'));
  });

  test('unconnected port does not duplicate internal signal', () async {
    final pMod = ParentMod(Logic(), Logic());
    await pMod.build();
    final sv = pMod.generateSynth();
    expect(RegExp('logic a[,;\n]').allMatches(sv).length, 2);
  });
}
