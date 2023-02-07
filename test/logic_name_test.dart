/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// logic_name_test.dart
/// Unit tests for logic name initialization
///
/// 2022 October 26
/// Author: Yao Jing Quek <yao.jing.quek@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/sanitizer.dart';
import 'package:test/test.dart';

class LogicTestModule extends Module {
  LogicTestModule(Logic a) {
    addInput(a.name, a, width: a.width);
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
}
