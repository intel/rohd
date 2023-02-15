/// Copyright (C) 2021-2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// simulator_test.dart
/// Unit tests for the ROHD simulator
///
/// 2021 May 7
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'dart:async';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('simulator supports registration of actions at time stamps', () async {
    var actionTaken = false;
    Simulator.registerAction(100, () => actionTaken = true);
    await Simulator.run();
    expect(actionTaken, equals(true));
  });

  test('simulator stops at maximum time', () async {
    const timeLimit = 1000;
    Simulator.setMaxSimTime(timeLimit);
    void register100inFuture() {
      // print('@${Simulator.time} registering again!');
      Simulator.registerAction(Simulator.time + 100, register100inFuture);
    }

    register100inFuture();
    await Simulator.run();
    expect(Simulator.time, lessThanOrEqualTo(timeLimit));
  });

  test('simulator stops when endSimulation is called', () async {
    var tooFar = false;
    var farEnough = false;
    const haltTime = 650;
    Simulator.registerAction(100, () => farEnough = true);
    Simulator.registerAction(1000, () => tooFar = true);
    Simulator.registerAction(haltTime, Simulator.endSimulation);
    await Simulator.run();
    expect(Simulator.time, equals(haltTime));
    expect(tooFar, equals(false));
    expect(farEnough, equals(true));
  });

  test('simulator reset waits for simulation to complete', () async {
    Simulator.registerAction(100, Simulator.endSimulation);
    Simulator.registerAction(100, () {
      unawaited(Simulator.reset());
    });
    Simulator.registerAction(100, () => true);
    await Simulator.run();
  });

  test('simulator end of action waits before ending', () async {
    var endOfSimActionExecuted = false;
    Simulator.registerAction(100, () => true);
    Simulator.registerEndOfSimulationAction(
        () => endOfSimActionExecuted = true);
    unawaited(Simulator.simulationEnded
        .then((value) => expect(endOfSimActionExecuted, isTrue)));
    await Simulator.run();
  });

  test('simulator end of action waits async before ending', () async {
    var endOfSimActionExecuted = false;
    Simulator.registerAction(100, () => true);
    Simulator.registerEndOfSimulationAction(() async {
      await Future<void>.delayed(const Duration(microseconds: 10));
      endOfSimActionExecuted = true;
    });
    await Simulator.run();
    expect(endOfSimActionExecuted, isTrue);
  });

  test('simulator waits for async registered actions to complete', () async {
    var registeredActionExecuted = false;
    Simulator.registerAction(100, () => true);
    Simulator.registerAction(50, () async {
      await Future<void>.delayed(const Duration(microseconds: 10));
      registeredActionExecuted = true;
    });
    await Simulator.run();
    expect(registeredActionExecuted, isTrue);
  });

  test('simulator waits for async injected actions to complete', () async {
    var injectedActionExecuted = false;
    Simulator.registerAction(100, () => true);
    Simulator.registerAction(50, () async {
      Simulator.injectAction(() async {
        await Future<void>.delayed(const Duration(microseconds: 10));
        injectedActionExecuted = true;
      });
    });
    await Simulator.run();
    expect(injectedActionExecuted, isTrue);
  });
}
