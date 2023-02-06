/// Copyright (C) 2021-2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// trace_test.dart
///
/// 2021 July 22
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class FlyingOutputModule extends Module {
  FlyingOutputModule(Logic a) : super(name: 'flyingoutput') {
    a = addInput('a', a);
    final y = addOutput('y');
    y <= BadSubModuleOut(a).y;
  }
}

class BadSubModuleOut extends Module {
  final Logic y = Logic(name: 'y'); // bad
  BadSubModuleOut(Logic a) : super(name: 'badsubmoduleout') {
    a = addInput('a', a); // good
    y <= a;
  }
}

class FlyingInputModule extends Module {
  FlyingInputModule(Logic b) : super(name: 'flyinginput') {
    b = addInput('b', b);
    final x = addOutput('x');
    x <= BadSubModuleIn(b).x;
  }
}

class BadSubModuleIn extends Module {
  Logic get x => output('x'); // good
  BadSubModuleIn(Logic b) : super(name: 'badsubmodulein') {
    addOutput('x');
    x <= b; // bad
  }
}

class DoubledInputModule extends Module {
  DoubledInputModule(Logic a) : super(name: 'doubledinput') {
    final aInner = addInput('a', a);
    addInput('b', aInner);
  }
}

class DoubledGappedInputModule extends Module {
  DoubledGappedInputModule(Logic a) : super(name: 'doubledgappedinput') {
    final aInner = addInput('a', a);
    addInput('b', Logic()..gets(~aInner));
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('flying output', () async {
    final mod = FlyingOutputModule(Logic());
    expect(() async {
      await mod.build();
    }, throwsException);
  });

  test('flying input', () async {
    final mod = FlyingInputModule(Logic());
    expect(() async {
      await mod.build();
    }, throwsException);
  });

  test('doubled input', () async {
    final mod = DoubledInputModule(Logic());
    expect(() async {
      await mod.build();
    }, throwsException);
  });

  test('doubled gapped input', () async {
    final mod = DoubledGappedInputModule(Logic());
    expect(() async {
      await mod.build();
    }, throwsException);
  });
}
