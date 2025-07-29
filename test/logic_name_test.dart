// Copyright (C) 2022-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_name_test.dart
// Unit tests for logic name initialization
//
// 2022 October 26
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:collection/collection.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/sanitizer.dart';
import 'package:test/test.dart';
import 'logic_structure_test.dart' as logic_structure_test;

class MyStruct extends LogicStructure {
  final Logic ready;
  final Logic valid;

  factory MyStruct({String name = 'myStruct'}) => MyStruct._(
        Logic(name: 'ready'),
        Logic(name: 'valid'),
        name: name,
      );

  MyStruct._(this.ready, this.valid, {required String name})
      : super([ready, valid], name: name);

  @override
  MyStruct clone({String? name}) => MyStruct(name: name ?? this.name);
}

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

class SensitiveNaming extends Module {
  SensitiveNaming(Logic a) {
    a = addInput('a', a);
    final b = Logic(name: 'b');
    final clk = Logic(name: 'myClock');
    b <= a;
    final c = Logic(name: 'c');
    final d = Logic(name: 'd');
    d <= c;
    final e = addOutput('e');
    e <= a & d;
    c <= flop(clk, b);
  }
}

class BusSubsetNaming extends Module {
  BusSubsetNaming(Logic a) {
    a = addInput('a', a, width: 32);
    final b = Logic(name: 'b', width: 32);
    b <= flop(Logic(name: 'clk'), a);
    final c = Logic(name: 'c');
    c <= b[3];
    final d = addOutput('d');
    d <= c;
  }
}

class BadlyNamedIntermediateSignalModule extends Module {
  BadlyNamedIntermediateSignalModule(Logic a) {
    a = addInput('a', a);

    final intermediate = Logic(name: '*wow&^(*&^)');

    intermediate <= ~a;

    addOutput('b') <= ~intermediate;
    addOutput('c') <= intermediate;
  }
}

class DrivenOutputModule extends Module {
  Logic get x => output('x');
  DrivenOutputModule(Logic? toDrive) {
    final a = addInput('a', Logic());
    addOutput('x');

    final internal = toDrive ?? Logic(name: 'internal');

    x <= mux(a, internal, a);
  }
}

class ModWithNameCollisionArrayPorts extends Module {
  Logic get o => output('o');
  ModWithNameCollisionArrayPorts(LogicArray portA, Logic portA2)
      : super(name: 'submod') {
    portA2 = addInput('portA_2', portA2);
    portA = addInputArray('portA', portA, dimensions: [3, 1]);
    addOutput('o') <= portA2;

    addOutput('portB_1');
    addOutputArray('portB', dimensions: [2, 1]);
  }
}

class NameCollisionArrayTop extends Module {
  NameCollisionArrayTop() {
    addOutput('o') <=
        ModWithNameCollisionArrayPorts(LogicArray([3, 1], 1), Logic()).o;
  }
}

class VariousNamingStruct extends LogicStructure {
  VariousNamingStruct({super.name = 'various_naming_struct'})
      : super([
          Logic(name: 'renameable', naming: Naming.renameable),
          Logic(name: 'reserved_$name', naming: Naming.reserved),
          Logic(name: 'mergeable', naming: Naming.mergeable),
          Logic(name: 'unnamed', naming: Naming.unnamed),
          MyStruct(name: 'my_sub_struct'),
        ]);

  @override
  VariousNamingStruct clone({String? name}) => VariousNamingStruct(name: name);
}

class StructElementNamingModule extends Module {
  StructElementNamingModule(VariousNamingStruct inp) {
    inp = addTypedInput('inp', inp);
    final outp = addTypedOutput('outp', inp.clone);

    final intermediate = inp.clone(name: 'intermediate');

    for (var i = 0; i < inp.elements.length; i++) {
      intermediate.elements[i] <= ~inp.elements[i] ^ outp.elements[i];
    }

    outp <= inp;
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
    expect(bus.name, equals('_s'));
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
      }, throwsA((dynamic e) => e is EmptyReservedNameException));
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

  group('sensitive naming', () {
    test('assigns and gates', () async {
      final mod = SensitiveNaming(Logic());
      await mod.build();
      final sv = mod.generateSynth();
      expect(sv, contains('e = a & d'));
      expect(sv, contains('b = a'));
      expect(sv, contains('d = c'));
    });

    test('bus subset', () async {
      final mod = BusSubsetNaming(Logic(width: 32));
      await mod.build();
      final sv = mod.generateSynth();
      expect(sv, contains('c = b[3]'));
    });
  });

  group('floating signals', () {
    test('unconnected floating', () async {
      final mod = DrivenOutputModule(null);
      await mod.build();
      final sv = mod.generateSynth();

      // shouldn't add a Z in there if left floating
      expect(!sv.contains('z'), true);
    });

    test('driven to z', () async {
      final mod = DrivenOutputModule(Const('z'));
      await mod.build();
      final sv = mod.generateSynth();

      // should add a Z if it's explicitly added
      expect(sv, contains('z'));
    });
  });

  test('array port and simple port with _num name conflict', () async {
    final mod = NameCollisionArrayTop();
    await mod.build();
    final sv = mod.generateSynth();
    expect(
        sv,
        contains('submod(.portA_2(portA_2),.portA(portA),'
            '.o(o),'
            '.portB_1(portB_1),.portB(portB))'));
  });

  test('badly named intermediate signal sanitization', () async {
    final dut = BadlyNamedIntermediateSignalModule(Logic());

    await dut.build();

    final sv = dut.generateSynth();

    expect(sv, contains('_wow_______'));
  });

  test('struct elements contain their parent names', () async {
    final mod = StructElementNamingModule(VariousNamingStruct());
    await mod.build();

    final sv = mod.generateSynth();

    expect(sv, contains('assign outp[0] = outp_renameable;'));
    expect(sv, contains('assign outp[1] = reserved_outp;'));
    expect(sv, contains('assign outp[2] = outp_mergeable;'));
    expect(sv, contains('assign outp[4] = outp_my_sub_struct_ready;'));
    expect(sv, contains('assign outp[5] = outp_my_sub_struct_valid;'));
    expect(sv, contains('assign inp_renameable = inp[0];'));
    expect(sv, contains('assign reserved_inp = inp[1];'));
    expect(sv, contains('assign outp_mergeable = inp[2];'));
    expect(sv, contains('assign inp_my_sub_struct_ready = inp[4];'));
    expect(sv, contains('assign inp_my_sub_struct_valid = inp[5];'));
    expect(
        sv,
        contains('assign intermediate_renameable ='
            ' (~inp_renameable) ^ outp_renameable;'));
    expect(
        sv,
        contains('assign reserved_intermediate ='
            ' (~reserved_inp) ^ reserved_outp;'));
    expect(
        sv,
        contains('assign intermediate_mergeable ='
            ' (~outp_mergeable) ^ outp_mergeable;'));
    expect(sv, contains('intermediate_my_sub_struct_ready'));
    expect(sv, contains('intermediate_my_sub_struct_valid'));
  });

  group('clone', () {
    test('name selection', () {
      const originalName = 'original';
      for (final newName in ['new', null]) {
        for (final originalNaming in Naming.values) {
          for (final newNaming in [...Naming.values, null]) {
            final selectedName = newName ?? originalName;
            final selectedNaming = Naming.chooseCloneNaming(
              originalName: originalName,
              newName: newName,
              originalNaming: originalNaming,
              newNaming: newNaming,
            );

            final reason = 'original: ($originalName, ${originalNaming.name}),'
                ' new: ($newName, ${newNaming?.name})'
                ' => ($selectedName, ${selectedNaming.name})';

            if (newNaming != null) {
              expect(selectedNaming, newNaming, reason: reason);
            } else if (newName == null && newNaming == null) {
              expect(selectedNaming, Naming.mergeable, reason: reason);
            } else if (newName != null && newNaming == null) {
              expect(selectedNaming, Naming.renameable, reason: reason);
            } else {
              fail('Undefined scenario: $reason');
            }
          }
        }
      }
    });

    group('logic', () {
      test('name null', () {
        final c = Logic(name: 'a').clone();
        expect(c.name, 'a');
        expect(c.naming, Naming.mergeable);
      });

      test('name provided', () {
        final c = Logic(name: 'a').clone(name: 'b');
        expect(c.name, 'b');
        expect(c.naming, Naming.renameable);
      });

      test('net', () {
        final c = LogicNet(name: 'a').clone();
        expect(c.name, 'a');
        expect(c.naming, Naming.mergeable);
        expect(c, isA<LogicNet>());
      });
    });

    group('logic structure', () {
      test('name null', () {
        final c = MyStruct().clone();
        expect(c.name, 'myStruct');
        expect(c.naming, Naming.unnamed);
      });

      test('name provided', () {
        final c = MyStruct().clone(name: 'newName');
        expect(c.name, 'newName');
        expect(c.naming, Naming.unnamed);
      });
    });

    group('logic array', () {
      test('name null', () {
        final c = LogicArray([1, 2], 3, name: 'a').clone();
        expect(c.name, 'a');
        expect(c.naming, Naming.mergeable);
      });

      test('name provided', () {
        final c = LogicArray([1, 2], 3, name: 'a').clone(name: 'b');
        expect(c.name, 'b');
        expect(c.naming, Naming.renameable);
      });

      test('net', () {
        final c = LogicArray.net([1, 2], 3, name: 'a').clone();
        expect(c.name, 'a');
        expect(c.naming, Naming.mergeable);
        expect(c.isNet, true);
      });
    });
  });

  group('named', () {
    test('logic', () {
      final a = Logic(name: 'a');
      final b = a.named('b');

      a.put(1);

      expect(b.value.toInt(), 1);
      expect(b.name, 'b');
      expect(b.naming, Naming.renameable);
    });

    test('logic with naming', () {
      final a = Logic(name: 'a');
      final b = a.named('b', naming: Naming.reserved);

      a.put(1);

      expect(b.value.toInt(), 1);
      expect(b.name, 'b');
      expect(b.naming, Naming.reserved);
    });

    test('net', () {
      final a = LogicNet(name: 'a');
      final b = a.named('b');

      a.put(1);

      expect(b.value.toInt(), 1);
      expect(b.name, 'b');
      expect(b.naming, Naming.renameable);
      expect(b.isNet, true);
      expect(b, isA<LogicNet>());
    });

    test('array', () {
      final a = LogicArray([1, 2], 3, name: 'a', numUnpackedDimensions: 1);
      final b = a.named('b');

      a.elements[0].elements[0].put(1);

      final listEq = const ListEquality<int>().equals;

      expect(b.elements[0].elements[0].value.toInt(), 1);
      expect(listEq(b.dimensions, a.dimensions), true);
      expect(b.numUnpackedDimensions, a.numUnpackedDimensions);
      expect(b.name, 'b');
      expect(b.naming, Naming.renameable);
    });

    test('array net with naming', () {
      final a = LogicArray.net([1, 2], 3, name: 'a', numUnpackedDimensions: 1);
      final b = a.named('b', naming: Naming.reserved);

      a.elements[0].elements[0].put(1);

      final listEq = const ListEquality<int>().equals;

      expect(b.elements[0].elements[0].value.toInt(), 1);
      expect(listEq(b.dimensions, a.dimensions), true);
      expect(b.numUnpackedDimensions, a.numUnpackedDimensions);
      expect(b.name, 'b');
      expect(b.naming, Naming.reserved);
      expect(b.isNet, true);
      expect(b, isA<LogicArray>());
    });

    test('structure', () {
      final a = logic_structure_test.MyFancyStruct();
      final b = a.named(
        'b',

        // naming should have no effect
        naming: Naming.reserved,
      );

      expect(b.name, 'b');

      expect(b.width, a.width);
      expect(b.elements[0], isA<LogicArray>());
      expect(b.elements[0].name, a.elements[0].name);
      expect(b.elements[0].naming, Naming.renameable);

      expect(b.elements[1], isA<Logic>());
      expect(b.elements[1].name, a.elements[1].name);
      expect(b.elements[1].naming, Naming.renameable);

      expect(b.elements[2], isA<logic_structure_test.MyStruct>());
      expect(b.elements[2].name, a.elements[2].name);
      expect(b.elements[2].naming, a.elements[2].naming);
      expect(b.elements[2].elements[0].name, a.elements[2].elements[0].name);

      a.arr.elements[0].put(1);

      expect(b.elements[0].elements[0].value.toInt(), 1);
    });
  });
}
