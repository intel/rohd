// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_test.dart
// Unit tests for Module APIs
//
// 2023 September 11
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class ModuleWithMaybePorts extends Module {
  Logic? get i => tryInput('i');
  Logic? get o => tryOutput('o');
  ModuleWithMaybePorts({required bool addIn, required bool addOut}) {
    if (addIn) {
      addInput('i', Logic());
    }
    if (addOut) {
      addOutput('o');
    }
  }
}

void main() {
  test('tryInput, exists', () {
    final mod = ModuleWithMaybePorts(addIn: true, addOut: false);
    expect(mod.i, isNotNull);
  });

  test('tryInput, doesnt exist', () {
    final mod = ModuleWithMaybePorts(addIn: false, addOut: false);
    expect(mod.i, null);
  });

  test('tryOutput, exists', () {
    final mod = ModuleWithMaybePorts(addIn: false, addOut: true);
    expect(mod.o, isNotNull);
  });

  test('tryOutput, doesnt exist', () {
    final mod = ModuleWithMaybePorts(addIn: false, addOut: false);
    expect(mod.o, null);
  });
}
