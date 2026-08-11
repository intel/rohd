// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemc_ffi_cosim_test.dart
// Demonstrates FFI-based SystemC co-simulation with existing ROHD tests.
//
// 2026 May
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
@Tags(['ffi'])
library;
// ignore_for_file: avoid_print

import 'dart:async';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/systemc_cosim_ffi.dart';
import 'package:test/test.dart';

// ═══════════════════════════════════════════════════════════════════════════
// DUT: A simple counter (same as systemc_simcompare_test.dart)
// ═══════════════════════════════════════════════════════════════════════════

class SimpleCounter extends Module {
  Logic get val => output('val');

  SimpleCounter(Logic clk, Logic reset, Logic en)
      : super(name: 'SimpleCounter') {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);
    en = addInput('en', en);
    final val = addOutput('val', width: 8);

    final nextVal = Logic(name: 'nextVal', width: 8);

    Sequential(clk, reset: reset, [
      If(en, then: [nextVal < nextVal + 1], orElse: [nextVal < nextVal]),
    ]);

    val <= nextVal;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Test that runs identically against both ROHD sim and SystemC FFI cosim
// ═══════════════════════════════════════════════════════════════════════════

void main() {
  tearDown(() async {
    await Simulator.reset();
  });
  tearDownAll(SystemCFfiCosim.cleanupCache);

  /// The core test logic — parametrized so it can run against either the
  /// native ROHD module or the SystemC FFI co-simulated module.
  ///
  /// [getVal] provides the output signal to check (from ROHD or cosim).
  Future<void> counterTest({
    required Logic Function() getVal,
    required Logic clk,
    required Logic reset,
    required Logic en,
  }) async {
    Simulator.setMaxSimTime(200);
    unawaited(Simulator.run());

    // Reset
    reset.inject(1);
    en.inject(0);
    await clk.nextPosedge;
    await clk.nextPosedge;
    reset.inject(0);
    await clk.nextPosedge;

    // Enable counting
    en.inject(1);
    await clk.nextPosedge;

    // After first posedge with en=1, counter should have incremented
    // previousValue = 0 (value before this edge)
    // value = 1 (updated at this edge)
    expect(getVal().previousValue!.toInt(), 0);
    expect(getVal().value.toInt(), 1);

    await clk.nextPosedge;
    expect(getVal().previousValue!.toInt(), 1);
    expect(getVal().value.toInt(), 2);

    await clk.nextPosedge;
    expect(getVal().value.toInt(), 3);

    // Disable — counter should freeze
    en.inject(0);
    await clk.nextPosedge;
    expect(getVal().value.toInt(), 3);

    await clk.nextPosedge;
    expect(getVal().value.toInt(), 3);

    // Re-enable
    en.inject(1);
    await clk.nextPosedge;
    expect(getVal().value.toInt(), 4);

    await Simulator.endSimulation();
  }

  // ─────────────────────────────────────────────────────────────────────
  // Test 1: Pure ROHD simulation (baseline)
  // ─────────────────────────────────────────────────────────────────────

  test('counter - ROHD native simulation', () async {
    final clk = SimpleClockGenerator(10).clk;
    final reset = Logic(name: 'reset');
    final en = Logic(name: 'en');
    final counter = SimpleCounter(clk, reset, en);
    await counter.build();

    await counterTest(
      getVal: () => counter.val,
      clk: clk,
      reset: reset,
      en: en,
    );
  });

  // ─────────────────────────────────────────────────────────────────────
  // Test 2: SystemC FFI co-simulation (same test logic!)
  // ─────────────────────────────────────────────────────────────────────

  test('counter - SystemC FFI cosimulation', () async {
    final clk = SimpleClockGenerator(10).clk;
    final reset = Logic(name: 'reset');
    final en = Logic(name: 'en');
    final counter = SimpleCounter(clk, reset, en);
    await counter.build();

    // Create the FFI cosim — this compiles the SystemC .so and hooks
    // into the Simulator's clkStable phase.
    final cosim = await SystemCFfiCosim.create(
      counter,
      clk: clk,
    );

    // If SystemC isn't installed, skip gracefully
    if (cosim == null) {
      print('SystemC not available — skipping FFI cosim test');
      return;
    }

    try {
      await counterTest(
        // Use the same output signal — the cosim module puts() values
        // onto it at clkStable, overriding the ROHD-computed values.
        getVal: () => counter.val,
        clk: clk,
        reset: reset,
        en: en,
      );
    } finally {
      await cosim.dispose();
    }
  });

  // ─────────────────────────────────────────────────────────────────────
  // Test 3: Negedge checking (inject → await negedge → expect pattern)
  // ─────────────────────────────────────────────────────────────────────

  /// Test logic that uses negedge for combinational settling checks.
  /// Pattern: inject at posedge → await negedge (immediate next edge) → check
  Future<void> counterNegedgeTest({
    required Logic Function() getVal,
    required Logic clk,
    required Logic reset,
    required Logic en,
  }) async {
    Simulator.setMaxSimTime(200);
    unawaited(Simulator.run());

    // Reset
    reset.inject(1);
    en.inject(0);
    await clk.nextPosedge;
    await clk.nextPosedge;

    // De-assert reset at posedge, check settled at negedge
    reset.inject(0);
    await clk.nextNegedge; // immediate next edge — no posedge in between
    expect(getVal().value.toInt(), 0); // counter still 0

    // Enable at posedge: inject en=1 at the posedge tick itself
    await clk.nextPosedge; // posedge fires with en=0 (inject hasn't happened)
    en.inject(1); // will take effect at NEXT mainTick
    await clk.nextNegedge; // settle — en is now 1 but Sequential already
    // fired at this posedge with en=0
    expect(getVal().value.toInt(), 0); // still 0

    // Next posedge: Sequential sees en=1
    await clk.nextPosedge;
    expect(getVal().value.toInt(), 1); // incremented!

    // Check at negedge: value stable between edges
    await clk.nextNegedge;
    expect(getVal().value.toInt(), 1); // unchanged

    // Another posedge
    await clk.nextPosedge;
    expect(getVal().value.toInt(), 2);

    // Disable at posedge, check at negedge
    en.inject(0);
    await clk.nextNegedge;
    expect(getVal().value.toInt(), 2); // still 2

    // Confirm stays 2 after next posedge with en=0
    await clk.nextPosedge;
    expect(getVal().value.toInt(), 2);

    await Simulator.endSimulation();
  }

  test('counter negedge - ROHD native simulation', () async {
    final clk = SimpleClockGenerator(10).clk;
    final reset = Logic(name: 'reset');
    final en = Logic(name: 'en');
    final counter = SimpleCounter(clk, reset, en);
    await counter.build();

    await counterNegedgeTest(
      getVal: () => counter.val,
      clk: clk,
      reset: reset,
      en: en,
    );
  });

  test('counter negedge - SystemC FFI cosimulation', () async {
    final clk = SimpleClockGenerator(10).clk;
    final reset = Logic(name: 'reset');
    final en = Logic(name: 'en');
    final counter = SimpleCounter(clk, reset, en);
    await counter.build();

    final cosim = await SystemCFfiCosim.create(
      counter,
      clk: clk,
    );

    if (cosim == null) {
      print('SystemC not available — skipping FFI cosim test');
      return;
    }

    try {
      await counterNegedgeTest(
        getVal: () => counter.val,
        clk: clk,
        reset: reset,
        en: en,
      );
    } finally {
      await cosim.dispose();
    }
  });
}
