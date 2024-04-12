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

class FlexibleModule extends Module {
  FlexibleModule({super.name});
}

class SelfContainingHier extends Module {
  SelfContainingHier() : super(name: 'self_containing_hier') {
    final aDriver = Logic();
    final a = addInput('a', aDriver);

    final mid = FlexibleModule(name: 'mid');
    final aMid = mid.addInput('a', a);

    final sub = FlexibleModule(name: 'sub');
    final aSub = sub.addInput('a', aMid);

    aDriver <= aSub.and();
  }
}

class MultipleLocation extends Module {
  MultipleLocation() {
    final a = addInput('a', Logic());
    final b = addInput('b', Logic());

    final sub1 = FlexibleModule(name: 'sub1');
    final subA = sub1.addInput('a', a);
    final sub2 = FlexibleModule(name: 'sub2');
    final subB = sub2.addInput('b', b);

    subA & subB;
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

  test('self-containing hierarchy', () async {
    final mod = SelfContainingHier();
    expect(mod.build, throwsA(isA<InvalidHierarchyException>()));
  });

  test('multiple location hierarchy', () async {
    final mod = MultipleLocation();
    expect(mod.build, throwsA(isA<PortRulesViolationException>()));
  });
}
