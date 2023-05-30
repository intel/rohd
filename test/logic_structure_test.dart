// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_structure_test.dart
// Tests for LogicStructure
//
// 2023 May 5
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

//TODO: check coverage
//TODO: test structures in conditional assignments
//TODO: test structures in If/Case expressions

class MyStruct extends LogicStructure {
  final Logic ready;
  final Logic valid;

  factory MyStruct() => MyStruct._(
        Logic(name: 'ready'),
        Logic(name: 'valid'),
      );

  MyStruct._(this.ready, this.valid) : super([ready, valid], name: 'myStruct');
}

class MyFancyStruct extends LogicStructure {
  final LogicArray arr;
  final Logic bus;
  final LogicStructure subStruct;

  factory MyFancyStruct({int busWidth = 12}) => MyFancyStruct._(
        LogicArray([3, 3], 8, name: 'arr'),
        Logic(name: 'bus', width: busWidth),
        MyStruct(),
      );

  MyFancyStruct._(this.arr, this.bus, this.subStruct)
      : super([arr, bus, subStruct], name: 'myFancyStruct');
}

class ModStructPort extends Module {
  ModStructPort(MyStruct struct) {
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

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('LogicStructure construction', () {
    test('simple construction', () {
      final s = LogicStructure([
        Logic(),
        Logic(),
      ], name: 'structure');

      expect(s.name, 'structure');
    });
  });

  group('LogicStructures with modules', () {
    test('simple struct bi-directional', () async {
      final struct = MyStruct();
      final mod = ModStructPort(struct);
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
}
