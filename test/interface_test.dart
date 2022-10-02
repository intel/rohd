/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// interface_test.dart
/// Tests for Interface
///
/// 2021 November 30
/// Author: Max Korbel <max.korbel@intel.com>
///

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

void main() {
  tearDown(Simulator.reset);

  group('uniquified interfaces', () {
    test('get uniquified ports', () async {
      final m = MyModule(MyModuleInterface(), MyModuleInterface());
      await m.build();
      expect(m.i1.getPorts({MyDirection.dir1}).length, 1);
      expect(m.i2.getPorts({MyDirection.dir2}).length, 1);
    });
  });
}
