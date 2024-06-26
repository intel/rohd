// Copyright (C) 2022-2024 Intel Corporation
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
    final sv = mod.generateSynth();

    // make sure we instantiate the external module properly
    expect(
        sv,
        contains(
            'external_module_name #(.WIDTH(2)) external_module(.a(a),.b(b));'));

    // make sure we don't generate the external module SV definition
    expect(RegExp(r'module\s+external_module_name').hasMatch(sv), isFalse);
  });
}
