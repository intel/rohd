/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// external_test.dart
/// Unit tests for external modules
///
/// 2022 January 7
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class MyExternalModule extends ExternalSystemVerilogModule {
  MyExternalModule(Logic a, {int width = 2})
      : super(
            topModuleName: 'external_module_name',
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
    var mod = TopModule(Logic(width: 2));
    await mod.build();
    var sv = mod.generateSynth();
    expect(
        sv,
        contains(
            'external_module_name #(.WIDTH(2)) external_module(.a(a),.b(b));'));
  });
}
