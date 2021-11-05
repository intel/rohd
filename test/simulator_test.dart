/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
/// 
/// simulator_test.dart
/// Unit tests for the ROHD simulator
/// 
/// 2021 May 7
/// Author: Max Korbel <max.korbel@intel.com>
/// 

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {

  tearDown(() {
    Simulator.reset();
  });

  test('simulator supports registration of actions at time stamps', () async {
    var actionTaken = false;
    Simulator.registerAction(100, () => actionTaken = true);
    await Simulator.run();
    expect(actionTaken, equals(true));
  });

  test('simulator stops at maximum time', () async {
    var timeLimit = 1000;
    Simulator.setMaxSimTime(timeLimit);
    void register100inFuture() {
      // print('@${Simulator.time} registering again!');
      Simulator.registerAction(
        Simulator.time+100,
        () => register100inFuture()
      );
    }
    register100inFuture();
    await Simulator.run();
    expect(Simulator.time, lessThanOrEqualTo(timeLimit));
  });

  test('simulator stops when endSimulation is called', () async {
    var tooFar = false;
    var farEnough = false;
    var haltTime = 650;
    Simulator.registerAction(100, () => farEnough = true);
    Simulator.registerAction(1000, () => tooFar = true);
    Simulator.registerAction(haltTime, () => Simulator.endSimulation());
    await Simulator.run();
    expect(Simulator.time, equals(haltTime));
    expect(tooFar, equals(false));
    expect(farEnough, equals(true));
  });
}