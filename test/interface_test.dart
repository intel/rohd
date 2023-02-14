/// Copyright (C) 2021-2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// interface_test.dart
/// Tests for Interface
///
/// 2021 November 30
/// Author: Max Korbel <max.korbel@intel.com>
///

// ignore_for_file: avoid_multiple_declarations_per_line

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

enum MyDirection { dir1, dir2 }

class MyModuleInterface extends Interface<MyDirection> {
  MyModuleInterface() {
    setPorts([Port('p1')], [MyDirection.dir1]);
    setPorts([Port('p2')], [MyDirection.dir2]);
  }
}

class MyModule extends Module {
  late final MyModuleInterface i1, i2;
  MyModule(MyModuleInterface i1, MyModuleInterface i2) {
    this.i1 = MyModuleInterface()
      ..connectIO(this, i1, uniquify: (oldName) => 'i1$oldName');
    this.i2 = MyModuleInterface()
      ..connectIO(this, i2, uniquify: (oldName) => 'i2$oldName');
  }
}

class UncleanPortInterface extends Interface<MyDirection> {
  UncleanPortInterface() {
    setPorts([Port('end')], [MyDirection.dir1]);
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('uniquified interfaces', () {
    test('get uniquified ports', () async {
      final m = MyModule(MyModuleInterface(), MyModuleInterface());
      await m.build();
      expect(m.i1.getPorts({MyDirection.dir1}).length, 1);
      expect(m.i2.getPorts({MyDirection.dir2}).length, 1);
    });
  });

  test('should return exception when port name is not sanitary.', () async {
    expect(() async {
      UncleanPortInterface();
    }, throwsException);
  });
}
