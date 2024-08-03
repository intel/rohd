// Copyright (C) 2023-2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_test.dart
// Unit tests for Module APIs
//
// 2023 September 11
// Author: Max Korbel <max.korbel@intel.com>

import 'package:collection/collection.dart';
import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class ModuleWithMaybePorts extends Module {
  Logic? get i => tryInput('i');
  Logic? get o => tryOutput('o');
  Logic? get io => tryInOut('io');
  ModuleWithMaybePorts(
      {bool addIn = false, bool addOut = false, bool addIo = false}) {
    if (addIn) {
      addInput('i', Logic());
    }
    if (addOut) {
      addOutput('o');
    }
    if (addIo) {
      addInOut('io', LogicNet());
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

class ArrayConcatMod extends Module {
  ArrayConcatMod() {
    final a = addInput('a', Logic());
    final en = addInput('en', Logic());
    final b = addOutput('b');

    final aBar = Logic(name: 'a_bar');
    final orOut = Logic(name: 'or_out');

    final t0 = Logic(name: 't0');
    final t2 = Logic(name: 't2');
    final t3 = Logic(name: 't3');
    final aConcat = LogicArray([4], 1, name: 'a_concat');

    aConcat.elements[3] <= t3;
    aConcat.elements[2] <= t2;
    aConcat.elements[1] <= a;
    aConcat.elements[0] <= t0;

    aBar <= ~aConcat.elements[1];

    orOut <= aBar | en;

    b <= aConcat.elements[1] & orOut;
  }
}

class UnconnectedArraySig extends Module {
  UnconnectedArraySig(Logic a) : super(name: 'unconnected_array_sig') {
    a = addInput('a', a);

    final aArr = LogicArray([2], 1, name: 'a_arr');
    aArr.elements[0] <= a;
    aArr.elements[1] <= Logic(name: 'unconnected');

    SubModWithArray(aArr);
  }
}

class SubModWithArray extends Module {
  SubModWithArray(LogicArray aArr) : super(name: 'sub_mod_with_array') {
    aArr = addInputArray('a_arr', aArr, dimensions: aArr.dimensions);
  }
}

void main() {
  group('try ports', () {
    test('tryInput, exists', () {
      final mod = ModuleWithMaybePorts(addIn: true);
      expect(mod.i, isNotNull);
    });

    test('tryInput, doesnt exist', () {
      final mod = ModuleWithMaybePorts();
      expect(mod.i, null);
    });

    test('tryOutput, exists', () {
      final mod = ModuleWithMaybePorts(addOut: true);
      expect(mod.o, isNotNull);
    });

    test('tryOutput, doesnt exist', () {
      final mod = ModuleWithMaybePorts();
      expect(mod.o, null);
    });

    test('tryInOut, exists', () {
      final mod = ModuleWithMaybePorts(addIo: true);
      expect(mod.io, isNotNull);
    });

    test('tryInOut, doesnt exist', () {
      final mod = ModuleWithMaybePorts();
      expect(mod.io, null);
    });
  });

  group('port sources', () {
    test('input port source', () {
      final src = Logic();
      final mod = FlexibleModule()..addInput('a', src);
      expect(mod.inputSource('a'), src);
    });

    test('inout port source', () {
      final src = LogicNet();
      final mod = FlexibleModule()..addInOut('a', src);
      expect(mod.inOutSource('a'), src);
    });

    test('input array port source', () {
      final src = LogicArray([1], 1);
      final mod = FlexibleModule()..addInputArray('a', src);
      expect(mod.inputSource('a'), src);
    });

    test('inout array port source', () {
      final src = LogicArray([1], 1);
      final mod = FlexibleModule()..addInOutArray('a', src);
      expect(mod.inOutSource('a'), src);
    });
  });

  test('self-containing hierarchy', () async {
    final mod = SelfContainingHier();
    expect(mod.build, throwsA(isA<InvalidHierarchyException>()));
  });

  test('multiple location hierarchy', () async {
    final mod = MultipleLocation();
    expect(mod.build, throwsA(isA<PortRulesViolationException>()));
  });

  test('array concat per element builds and finds sigs', () async {
    final mod = ArrayConcatMod();
    await mod.build();

    expect(
        mod.internalSignals.firstWhereOrNull((e) => e.name == 't0'), isNotNull);

    final sv = mod.generateSynth();
    expect(sv, contains('assign a_concat[0] = t0;'));
  });

  test('array unconnected input port found', () async {
    final mod = UnconnectedArraySig(Logic());
    await mod.build();

    expect(mod.internalSignals.firstWhereOrNull((e) => e.name == 'unconnected'),
        isNotNull);

    final sv = mod.generateSynth();
    expect(sv, contains('assign a_arr[1] = unconnected;'));
  });
}
