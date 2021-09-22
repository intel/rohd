/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
/// 
/// trace_dest.dart
/// 
/// 2021 July 22
/// Author: Max Korbel <max.korbel@intel.com>
/// 

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';


class FlyingOutputModule extends Module {
  FlyingOutputModule(Logic a) : super(name: 'flyingoutput') {
    a = addInput('a', a);
    var y = addOutput('y');
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
    var x = addOutput('x');
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

void main() {
  
  tearDown(() {
    Simulator.reset();
  });

  test('flying output', () async {
    var mod = FlyingOutputModule(Logic());
    expect(() async { await mod.build(); }, throwsException);
  });

  test('flying input', () async {
    var mod = FlyingInputModule(Logic());
    expect(() async { await mod.build(); }, throwsException);
  });
  
}