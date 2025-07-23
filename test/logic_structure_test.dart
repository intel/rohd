// Copyright (C) 2023-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_structure_test.dart
// Tests for LogicStructure
//
// 2023 May 5
// Author: Max Korbel <max.korbel@intel.com>

import 'dart:async';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

/// This is the struct used in the logic structures documentation.
class ReadyValidStruct extends LogicStructure {
  final Logic ready;
  final Logic valid;

  factory ReadyValidStruct({String name = 'readyValid'}) => ReadyValidStruct._(
        Logic(name: 'ready'),
        Logic(name: 'valid'),
        name: name,
      );

  ReadyValidStruct._(this.ready, this.valid, {required String name})
      : super([ready, valid], name: name);

  @override
  ReadyValidStruct clone({String? name}) =>
      ReadyValidStruct(name: name ?? this.name);
}

class MyStruct extends LogicStructure {
  final Logic ready;
  final Logic valid;

  factory MyStruct({String name = 'myStruct'}) => MyStruct._(
        Logic(name: 'ready'),
        Logic(name: 'valid'),
        name: name,
      );

  MyStruct._(this.ready, this.valid, {required super.name})
      : super([ready, valid]);

  @override
  MyStruct clone({String? name}) => MyStruct(name: name ?? this.name);
}

class MyFancyStruct extends LogicStructure {
  final LogicArray arr;
  final Logic bus;
  final LogicStructure subStruct;

  factory MyFancyStruct({int busWidth = 12, String name = 'myFancyStruct'}) =>
      MyFancyStruct._(
        LogicArray([3, 3], 8, name: 'arr'),
        Logic(name: 'bus', width: busWidth),
        MyStruct(),
        name: name,
      );

  MyFancyStruct._(this.arr, this.bus, this.subStruct,
      {super.name = 'myFancyStruct'})
      : super([arr, bus, subStruct]);

  @override
  MyFancyStruct clone({String? name}) =>
      MyFancyStruct(busWidth: bus.width, name: name ?? this.name);
}

class StructPortModule extends Module {
  StructPortModule(MyStruct struct) {
    final ready = addInput('ready', struct.ready);
    final valid = addOutput('valid');
    struct.valid <= valid;

    valid <= ready;
  }
}

class ModStructPassthrough extends Module {
  MyStruct get sOut => MyStruct()..gets(output('sOut'));

  ModStructPassthrough(MyStruct struct) {
    struct = MyStruct()..gets(addInput('sIn', struct, width: struct.width));
    addOutput('sOut', width: struct.width) <= struct;
  }
}

class FancyStructInverter extends Module {
  MyFancyStruct get sOut => MyFancyStruct()..gets(output('sOut'));

  FancyStructInverter(MyFancyStruct struct) {
    struct = MyFancyStruct()
      ..gets(addInput('sIn', struct, width: struct.width));
    addOutput('sOut', width: struct.width) <= ~struct;
  }
}

class StructModuleWithInstrumentation extends Module {
  StructModuleWithInstrumentation(Logic a) {
    a = addInput('a', a, width: 2);

    MyStruct()
      ..gets(a)
      ..value
      ..previousValue
      ..width
      ..srcConnection
      ..dstConnections
      ..parentModule
      ..parentStructure
      ..naming
      ..arrayIndex
      ..isArrayMember
      ..leafElements
      ..isInput
      ..isOutput
      ..changed
      ..glitch
      // ignore: deprecated_member_use_from_same_package
      ..hasValidValue()
      // ignore: deprecated_member_use_from_same_package
      ..isFloating()
      // ignore: deprecated_member_use_from_same_package
      ..valueBigInt
      // ignore: deprecated_member_use_from_same_package
      ..valueInt;

    unawaited(MyStruct().nextChanged);
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('example ready valid struct', () {
    expect(
        ReadyValidStruct(name: 'hello').clone(name: 'goodbye').name, 'goodbye');
  });

  test('late previousValue', () async {
    final s = MyStruct();
    final clk = SimpleClockGenerator(10).clk;
    Simulator.setMaxSimTime(200);

    var i = 0;
    clk.posedge.listen((_) => s.inject(i++));

    unawaited(Simulator.run());

    await clk.nextPosedge;
    await clk.nextPosedge;
    await clk.nextPosedge;

    expect(s.previousValue, isNotNull);
    expect(s.previousValue!.toInt(), 1);

    s.packed;
    await clk.nextPosedge;
    await clk.nextPosedge;
    expect(s.packed.previousValue, s.previousValue);
    await clk.nextPosedge;
    expect(s.packed.previousValue, s.previousValue);

    await Simulator.endSimulation();
  });

  test('instrumentation on struct does not make hardware', () async {
    final mod = StructModuleWithInstrumentation(Const(0, width: 2));
    await mod.build();

    final sv = mod.generateSynth();

    expect(sv.contains('swizzle'), isFalse,
        reason: 'Should not pack from instrumentation!');
  });

  group('LogicStructure construction', () {
    test('simple construction', () {
      final s = LogicStructure([
        Logic(),
        Logic(),
      ], name: 'structure');

      expect(s.name, 'structure');
    });

    test('sub logic in two structures throws exception', () {
      final s = LogicStructure([
        Logic(),
      ], name: 'structure');

      expect(() => LogicStructure([s.elements.first]),
          throwsA(isA<LogicConstructionException>()));
    });

    test('sub structure in two structures throws exception', () {
      final subS = LogicStructure([Logic()]);

      LogicStructure([
        subS,
      ], name: 'structure');

      expect(() => LogicStructure([subS]),
          throwsA(isA<LogicConstructionException>()));
    });

    test('structure clone', () {
      final orig = MyFancyStruct();
      final copy = orig.clone();

      expect(copy.name, orig.name);

      expect(copy.width, orig.width);
      expect(copy.elements[0], isA<LogicArray>());
      expect(copy.elements[0].name, orig.elements[0].name);
      expect(copy.elements[0].naming, Naming.renameable);

      expect(copy.elements[1], isA<Logic>());
      expect(copy.elements[1].name, orig.elements[1].name);
      expect(copy.elements[1].naming, Naming.renameable);

      expect(copy.elements[2], isA<MyStruct>());
      expect(copy.elements[2].name, orig.elements[2].name);
      expect(copy.elements[2].naming, orig.elements[2].naming);
      expect(
          copy.elements[2].elements[0].name, orig.elements[2].elements[0].name);

      expect(orig.clone(name: 'newName').name, 'newName');
    });

    test('tricky withSet', () async {
      // first field has width of 72 so this is the starting point
      // second field has a width of 12
      // try a withSet of a subset of the second field
      MyFancyStruct().withSet(72, Logic(width: 4));
    });
  });

  group('LogicStructures with modules', () {
    test('simple struct bi-directional', () async {
      final struct = MyStruct();
      final mod = StructPortModule(struct);
      await mod.build();

      final vectors = [
        Vector({'ready': 0}, {'valid': 0}),
        Vector({'ready': 1}, {'valid': 1}),
      ];

      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('simple passthrough struct', () async {
      final struct = MyStruct();
      final mod = ModStructPassthrough(struct);
      await mod.build();

      final vectors = [
        Vector({'sIn': 0}, {'sOut': 0}),
        Vector({'sIn': LogicValue.ofString('10')},
            {'sOut': LogicValue.ofString('10')}),
      ];

      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('fancy struct inverter', () async {
      final struct = MyFancyStruct();
      final mod = FancyStructInverter(struct);
      await mod.build();

      struct.arr.elements[2].elements[1].put(0x55);
      expect(mod.sOut.arr.elements[2].elements[1].value.toInt(), 0xaa);

      struct.bus.put(0x0f0);
      expect(mod.sOut.bus.value.toInt(), 0xf0f);

      final vectors = [
        Vector({'sIn': 0},
            {'sOut': LogicValue.filled(struct.width, LogicValue.one)}),
        Vector({'sIn': LogicValue.ofString('10' * (struct.width ~/ 2))},
            {'sOut': LogicValue.ofString('01' * (struct.width ~/ 2))}),
      ];

      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });
  });

  test('logicstructure value and previous value', () async {
    final s = MyStruct();

    final val1 = LogicValue.ofInt(1, 2);
    final val2 = LogicValue.ofInt(2, 2);

    s.put(val1);

    expect(s.value, val1);
    expect(s.previousValue, isNull);

    var checkRan = false;

    Simulator.registerAction(10, () {
      s.put(val2);
      expect(s.value, val2);
      expect(s.previousValue, val1);
      checkRan = true;
    });

    await Simulator.run();

    expect(checkRan, isTrue);
  });
}
