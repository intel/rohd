// Copyright (C) 2021-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// interface_test.dart
// Tests for Interface
//
// 2021 November 30
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

enum MyDirection { dir1, dir2 }

class MyModuleInterface extends Interface<MyDirection> {
  MyModuleInterface() {
    setPorts([Logic.port('p1'), LogicArray.port('p1arr')], [MyDirection.dir1]);
    setPorts(
        [LogicNet.port('p2'), LogicArray.netPort('p2arr')], [MyDirection.dir2]);
  }
}

class MyModule extends Module {
  MyModule(MyModuleInterface i1, MyModuleInterface i2) {
    MyModuleInterface().connectIO(this, i1,
        uniquify: (oldName) => 'i1$oldName',
        inOutTags: {MyDirection.dir2},
        inputTags: {MyDirection.dir1});
    MyModuleInterface().connectIO(this, i2,
        uniquify: (oldName) => 'i2$oldName',
        inOutTags: {MyDirection.dir2},
        outputTags: {MyDirection.dir1});
  }
}

class UncleanPortInterface extends Interface<MyDirection> {
  UncleanPortInterface() {
    setPorts([Logic.port('end')], [MyDirection.dir1]);
  }
}

class MaybePortInterface extends Interface<MyDirection> {
  Logic? get p => tryPort('p');

  MaybePortInterface({required bool includePort}) {
    if (includePort) {
      setPorts([Logic.port('p')], {MyDirection.dir1});
    }
  }
}

class BadNetInterface extends Interface<MyDirection> {
  BadNetInterface() {
    setPorts([Logic.port('p')], [MyDirection.dir1]);
    setPorts([LogicArray.port('a')], [MyDirection.dir2]);
  }
}

class BadNetModule extends Module {
  BadNetModule({bool badPort = false, bool badArr = false}) {
    BadNetInterface().connectIO(this, BadNetInterface(), inOutTags: {
      if (badPort) MyDirection.dir1,
      if (badArr) MyDirection.dir2,
    });
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

      expect(m.tryOutput('i2p1'), isNotNull);
      expect(m.tryOutput('i2p1arr'), isNotNull);

      expect(m.tryInput('i1p1'), isNotNull);
      expect(m.tryInput('i1p1arr'), isNotNull);

      expect(m.tryInOut('i1p2'), isNotNull);
      expect(m.tryInOut('i1p2arr'), isNotNull);
      expect(m.tryInOut('i2p2'), isNotNull);
      expect(m.tryInOut('i2p2arr'), isNotNull);
    });
  });

  test('should return exception when port name is not sanitary.', () async {
    expect(() async {
      UncleanPortInterface();
    }, throwsException);
  });

  group('bad net args intf', () {
    test('port', () {
      expect(
          () => BadNetModule(badPort: true), throwsA(isA<PortTypeException>()));
    });

    test('array', () {
      expect(
          () => BadNetModule(badArr: true), throwsA(isA<PortTypeException>()));
    });
  });

  group('maybe port', () {
    test('tryPort, exists', () {
      final intf = MaybePortInterface(includePort: true);
      expect(intf.p, isNotNull);
    });

    test('tryPort, doesnt exist', () {
      final intf = MaybePortInterface(includePort: false);
      expect(intf.p, null);
    });
  });
}
