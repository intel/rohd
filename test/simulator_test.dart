// Copyright (C) 2021-2025 Intel Corporation
// Copyright (C) 2024 Adam Rose
// SPDX-License-Identifier: BSD-3-Clause
//
// simulator_test.dart
// Unit tests for the ROHD simulator
//
// 2021 May 7
// Author: Max Korbel <max.korbel@intel.com>
//
// 2024 Feb 28th
// Amended by Adam Rose <adam.david.rose@gmail.com> for Rohme compatibility
//
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

  test('simulator supports cancelation of previously scheduled actions',
      () async {
    var actionCount = 0;

    void incrementCount() {
      actionCount++;
    }

    Simulator.registerAction(
        50, () => Simulator.cancelAction(100, incrementCount));
    Simulator.registerAction(100, incrementCount);
    Simulator.registerAction(200, incrementCount);

    await Simulator.run();
    expect(actionCount, equals(1));
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
    Simulator.registerAction(
        haltTime, () => unawaited(Simulator.endSimulation()));
    await Simulator.run();
    expect(Simulator.time, equals(haltTime));
    expect(tooFar, equals(false));
    expect(farEnough, equals(true));
  });

  test('simulator reset waits for simulation to complete', () async {
    Simulator.registerAction(100, () => unawaited(Simulator.endSimulation()));
    Simulator.registerAction(100, () {
      unawaited(Simulator.reset());
    });
    Simulator.registerAction(100, () => true);
    await Simulator.run();
  });

  group('simulator end of', () {
    test('action waits before ending', () async {
      var endOfSimActionExecuted = false;
      Simulator.registerAction(100, () => true);
      Simulator.registerEndOfSimulationAction(
          () => endOfSimActionExecuted = true);
      unawaited(Simulator.simulationEnded
          .then((value) => expect(endOfSimActionExecuted, isTrue)));
      await Simulator.run();
    });

    test('action waits async before ending', () async {
      var endOfSimActionExecuted = false;
      Simulator.registerAction(100, () => true);
      Simulator.registerEndOfSimulationAction(() async {
        await Future<void>.delayed(const Duration(microseconds: 10));
        endOfSimActionExecuted = true;
      });
      await Simulator.run();
      expect(endOfSimActionExecuted, isTrue);
    });

    test('action throws', () async {
      var endOfSimActionExecuted = false;
      var errorThrown = false;

      Simulator.registerAction(100, () => true);
      Simulator.registerEndOfSimulationAction(() {
        endOfSimActionExecuted = true;
        throw Exception('End of sim action failed');
      });

      // the Future will hang if we don't properly trigger the completion
      unawaited(Simulator.run().onError((_, __) {
        errorThrown = true;
      }));
      await Simulator.simulationEnded;

      expect(endOfSimActionExecuted, isTrue);
      expect(errorThrown, isTrue);
    });

    test('action async throws', () async {
      var endOfSimActionExecuted = false;
      var errorThrown = false;

      Simulator.registerAction(100, () => true);
      Simulator.registerEndOfSimulationAction(() async {
        await Future<void>.delayed(const Duration(microseconds: 10));
        endOfSimActionExecuted = true;
        throw Exception('End of sim action failed');
      });

      // the Future will hang if we don't properly trigger the completion
      unawaited(Simulator.run().onError((_, __) {
        errorThrown = true;
      }));
      await Simulator.simulationEnded;

      expect(endOfSimActionExecuted, isTrue);
      expect(errorThrown, isTrue);
    });

    test('actions still occur when simulation exception is thrown', () async {
      var errorThrown = false;
      var endOfSimActionExecuted = false;

      Simulator.registerAction(
          100,
          () => Simulator.throwException(
              Exception('simulator thrown exception'), StackTrace.current));
      Simulator.registerAction(200, () => true);

      Simulator.registerEndOfSimulationAction(() {
        endOfSimActionExecuted = true;
      });

      unawaited(Simulator.run().onError((_, __) {
        errorThrown = true;
      }));

      await Simulator.simulationEnded;

      expect(errorThrown, isTrue);
      expect(endOfSimActionExecuted, isTrue);
    });

    test('actions are cleared at Simulator.reset even if exception occurs',
        () async {
      var endOfSimActionExecuted = false;
      var errorThrown = false;

      Simulator.registerAction(
          100,
          () => Simulator.throwException(
              Exception('simulator thrown exception'), StackTrace.current));

      Simulator.registerEndOfSimulationAction(() {
        endOfSimActionExecuted = true;
      });

      await Simulator.run().onError((_, __) {
        errorThrown = true;
      });

      expect(endOfSimActionExecuted, isTrue);
      expect(errorThrown, isTrue);

      endOfSimActionExecuted = false;

      await Simulator.reset();

      Simulator.registerAction(100, () => true);

      await Simulator.run();

      expect(endOfSimActionExecuted, isFalse);
    });
  });

  test('registered action exception in simulator ends simulation', () async {
    var errorThrown = false;

    Simulator.registerAction(100, () => throw Exception('failed action'));
    Simulator.registerAction(200, () => true);

    unawaited(Simulator.run().onError((_, __) {
      errorThrown = true;
    }));

    await Simulator.simulationEnded;

    expect(errorThrown, isTrue);
  });

  test('simulator thrown exception ends simulation', () async {
    var errorThrown = false;

    Simulator.registerAction(
        100,
        () => Simulator.throwException(
            Exception('simulator thrown exception'), StackTrace.current));
    Simulator.registerAction(200, () => true);

    unawaited(Simulator.run().onError((_, __) {
      errorThrown = true;
    }));

    await Simulator.simulationEnded;

    expect(errorThrown, isTrue);
  });

  test('simulator end simulation waits for simulation to end', () async {
    final signal = Logic()..put(0);
    Simulator.setMaxSimTime(1000);
    Simulator.registerAction(100, () => signal.inject(1));
    unawaited(Simulator.run());
    await signal.nextPosedge;
    await Simulator.endSimulation();
    expect(Simulator.simulationHasEnded, isTrue);
    expect(Simulator.time, 100);
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

  test('simulator exception when registering action in the past', () async {
    Simulator.registerAction(100, () {
      Simulator.registerAction(50, () {});
    });

    expect(() async {
      await Simulator.run();
    }, throwsA(isA<SimulatorException>()));
  });

  group('Rohme compatibility tests', () {
    test('simulator supports delta cycles', () async {
      // ignore: omit_local_variable_types
      final List<String> testLog = [];

      void deltaFunc(int t, int i) {
        testLog.add('wake up $i');
        Simulator.registerAction(100, () => testLog.add('delta $i'));
      }

      Simulator.registerAction(100, () => deltaFunc(Simulator.time, 0));
      Simulator.registerAction(100, () => deltaFunc(Simulator.time, 1));

      await Simulator.run();

      // ignore: omit_local_variable_types
      final List<String> expectedLog = [
        'wake up 0',
        'wake up 1',
        'delta 0',
        'delta 1'
      ];
      expect(testLog, expectedLog);
    });

    test('simulator supports end of delta one shot callbacks', () async {
      var callbackCount = 0;

      // add a self cancelling listener
      Simulator.registerAction(
          100, () => Simulator.injectAction(() => callbackCount++));
      Simulator.registerAction(200, () {});

      await Simulator.run();
      expect(callbackCount, 1);
    });

    test('deltas occur after end of delta', () async {
      // ignore: omit_local_variable_types
      final List<String> testLog = [];

      void deltaFunc(int t, int i) {
        testLog.add('first delta $i');

        Simulator.registerAction(t, () {
          Simulator.registerAction(
              Simulator.time, () => testLog.add('next delta $i'));
          Simulator.injectAction(() => testLog.add('end delta $i'));
        });
      }

      Simulator.registerAction(100, () => deltaFunc(Simulator.time, 0));
      Simulator.registerAction(100, () => deltaFunc(Simulator.time, 1));

      await Simulator.run();

      // ignore: omit_local_variable_types
      final List<String> expectedLog = [
        'first delta 0',
        'first delta 1',
        'end delta 0',
        'end delta 1',
        'next delta 0',
        'next delta 1'
      ];

      expect(testLog, expectedLog);
    });
  });

  test('end of tick action happens at end of tick', () async {
    var injectedActionTaken = false;
    var endOfTickActionTaken = false;

    Simulator.registerAction(100, () {
      Simulator.injectAction(() {
        expect(Simulator.phase, equals(SimulatorPhase.mainTick));
        expect(injectedActionTaken, isFalse);
        expect(endOfTickActionTaken, isFalse);
        injectedActionTaken = true;
      });
      Simulator.injectEndOfTickAction(() {
        expect(Simulator.phase, equals(SimulatorPhase.clkStable));
        expect(injectedActionTaken, isTrue);
        expect(endOfTickActionTaken, isFalse);
        endOfTickActionTaken = true;
      });
    });

    await Simulator.run();

    expect(injectedActionTaken, isTrue);
    expect(endOfTickActionTaken, isTrue);
  });

  test('end of tick makes a re-tick if it was missed', () async {
    var endOfTickActionTaken = false;

    Simulator.registerAction(100, () async {
      unawaited(Simulator.postTick.first.then((_) {
        Simulator.injectEndOfTickAction(() => endOfTickActionTaken = true);
      }));
    });

    var numStartTicks = 0;
    Simulator.startTick.listen((_) {
      expect(Simulator.time, 100);
      numStartTicks++;
    });

    await Simulator.run();

    expect(endOfTickActionTaken, isTrue);
    expect(numStartTicks, equals(2));
  });
}
