// Copyright (C) 2022-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// external_test.dart
// Unit tests for external modules
//
// 2022 January 7
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class MyExternalModule extends ExternalSystemVerilogModule {
  MyExternalModule(Logic a, {int width = 2})
      : super(
            definitionName: 'external_module_name',
            parameters: {'WIDTH': '$width'}) {
    addInput('a', a, width: width);
    addOutput('b', width: width);
  }
}

class TopModule extends Module {
  TopModule(Logic a) {
    a = addInput('a', a, width: a.width);
    MyExternalModule(a);
  }
}

void main() {
  test('instantiate', () async {
    final mod = TopModule(Logic(width: 2));
    await mod.build();
    final sv = mod.dumpSystemVerilog();

    // make sure we instantiate the external module properly
    expect(
        sv,
        contains(
            'external_module_name #(.WIDTH(2)) external_module(.a(a),.b(b));'));

    // make sure we don't generate the external module SV definition
    expect(RegExp(r'module\s+external_module_name').hasMatch(sv), isFalse);
  });

  group('simple', () {
    test('instantiate without a subclass', () async {
      final a = Logic(width: 8);
      final b = Logic(width: 8);
      late final Logic sum;
      final top = _SimpleTop(a, b, (mod) => sum = mod.output('sum'));
      await top.build();
      final sv = top.dumpSystemVerilog();

      expect(sum.width, 9);
      expect(
          sv, contains('my_adder #(.WIDTH(8)) adder(.a(a),.b(b),.sum(sum));'));
      expect(RegExp(r'module\s+my_adder').hasMatch(sv), isFalse);
    });

    test('inputs and parameters are optional', () async {
      final top = _SimpleOutputOnlyTop();
      await top.build();
      expect(
          RegExp(r'const_gen\s+const_inst\(\.q\(q\)\);')
              .hasMatch(top.dumpSystemVerilog()),
          isTrue);
    });
  });
}

class _SimpleTop extends Module {
  _SimpleTop(Logic a, Logic b, void Function(Module mod) onCreate) {
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);
    final mod = ExternalSystemVerilogModule.simple(
      definitionName: 'my_adder',
      inputs: {'a': a, 'b': b},
      outputs: {'sum': 9},
      parameters: {'WIDTH': '8'},
      name: 'adder',
    );
    addOutput('sum', width: 9) <= mod.output('sum');
    onCreate(mod);
  }
}

class _SimpleOutputOnlyTop extends Module {
  _SimpleOutputOnlyTop() {
    final mod = ExternalSystemVerilogModule.simple(
      definitionName: 'const_gen',
      outputs: {'q': 1},
      name: 'const_inst',
    );
    addOutput('q') <= mod.output('q');
  }
}
