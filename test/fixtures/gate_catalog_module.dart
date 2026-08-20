// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// gate_catalog_module.dart
// A single ROHD module that instantiates every public gate API in
// `lib/src/modules/gates.dart` (plus a few closely related primitives:
// FlipFlop variants, TriStateBuffer, BusSubset, and Swizzle) so that the
// netlist synthesizer's cell-mapper coverage can be captured in one
// deterministic, checked-in JSON asset.
//
// Every instantiated gate's output (or, for multi-output gates, every
// output) is wired directly to a uniquely named top-level output port. This
// guarantees dead-cell elimination cannot prune any of the cells this file
// is meant to exercise.
//
// See `test/gate_catalog_test.dart` for the test that verifies the checked-in
// `test/fixtures/gate_catalog.rohd.json` asset still matches what this module
// produces, and `tool/generate_gate_catalog.dart` for the script that
// (re)generates that asset.
//
// 2026 August 20
// Author: Copilot <223556219+Copilot@users.noreply.github.com>

import 'package:rohd/rohd.dart';

/// A gate-catalog top-level module.
///
/// Instantiates one (or a small number of representative variants) of every
/// gate [Module] and top-level gate-building function exposed by
/// `lib/src/modules/gates.dart`, along with [FlipFlop] (in all mapper-
/// supported configurations), [TriStateBuffer], [BusSubset], and [Swizzle].
///
/// All inputs are plain free (unconnected) top-level signals; this module is
/// intended purely for structural (netlist) synthesis, not simulation.
class GateCatalog extends Module {
  /// Creates the gate catalog module.
  ///
  /// All inputs are supplied by the caller so that construction is fully
  /// deterministic and repeatable byte-for-byte across runs.
  GateCatalog({
    required Logic clk,
    required Logic en,
    required Logic reset,
    required Logic muxSel,
    required Logic enableTri,
    required Logic a4,
    required Logic b4,
    required Logic a8,
    required Logic b8,
    required Logic d4,
    required Logic shamt4,
    required Logic idx3,
    required Logic idx5,
    required Logic resetValueDyn4,
    required LogicNet busNet,
  }) : super(name: 'gate_catalog', definitionName: 'GateCatalog') {
    clk = addInput('clk', clk);
    en = addInput('en', en);
    reset = addInput('reset', reset);
    muxSel = addInput('muxSel', muxSel);
    enableTri = addInput('enableTri', enableTri);
    a4 = addInput('a4', a4, width: 4);
    b4 = addInput('b4', b4, width: 4);
    a8 = addInput('a8', a8, width: 8);
    b8 = addInput('b8', b8, width: 8);
    d4 = addInput('d4', d4, width: 4);
    shamt4 = addInput('shamt4', shamt4, width: 4);
    idx3 = addInput('idx3', idx3, width: 3);
    idx5 = addInput('idx5', idx5, width: 5);
    resetValueDyn4 = addInput('resetValueDyn4', resetValueDyn4, width: 4);
    final bus = addInOut('bus', busNet, width: 8);

    // ── NotGate → $not ───────────────────────────────────────────────
    addOutput('not_out', width: 8) <= ~a8;

    // ── And2Gate → $and (logic/logic and logic/const variants) ───────
    addOutput('and_ll_out', width: 8) <= a8 & b8;
    addOutput('and_lc_out', width: 8) <=
        And2Gate(a8, Const(0xaa, width: 8)).out;

    // ── Or2Gate → $or (logic/logic and logic/const variants) ─────────
    addOutput('or_ll_out', width: 8) <= a8 | b8;
    addOutput('or_lc_out', width: 8) <= Or2Gate(a8, Const(0x55, width: 8)).out;

    // ── Xor2Gate → $xor (logic/logic and logic/const variants) ───────
    addOutput('xor_ll_out', width: 8) <= a8 ^ b8;
    addOutput('xor_lc_out', width: 8) <=
        Xor2Gate(a8, Const(0x0f, width: 8)).out;

    // ── Unary reductions → $reduce_and / $reduce_or / $reduce_xor ─────
    addOutput('reduce_and_out') <= a8.and();
    addOutput('reduce_or_out') <= a8.or();
    addOutput('reduce_xor_out') <= a8.xor();

    // ── Add → $add (logic/logic and logic/const variants) ────────────
    final addLl = Add(a4, b4);
    addOutput('add_ll_sum', width: 4) <= addLl.sum;
    addOutput('add_ll_carry') <= addLl.carry;
    final addLc = Add(a4, 5);
    addOutput('add_lc_sum', width: 4) <= addLc.sum;
    addOutput('add_lc_carry') <= addLc.carry;

    // ── Subtract → $sub (logic/logic and logic/const variants) ───────
    addOutput('sub_ll_out', width: 4) <= a4 - b4;
    addOutput('sub_lc_out', width: 4) <= a4 - 3;

    // ── Multiply → $mul (logic/logic and logic/const variants) ───────
    addOutput('mul_ll_out', width: 4) <= a4 * b4;
    addOutput('mul_lc_out', width: 4) <= a4 * 3;

    // ── Divide → $div (logic/logic and logic/const variants) ─────────
    addOutput('div_ll_out', width: 4) <= a4 / b4;
    addOutput('div_lc_out', width: 4) <= a4 / 3;

    // ── Modulo → $mod (logic/logic and logic/const variants) ─────────
    addOutput('mod_ll_out', width: 4) <= a4 % b4;
    addOutput('mod_lc_out', width: 4) <= a4 % 3;

    // ── Power → $pow (logic/logic and logic/const variants) ──────────
    addOutput('pow_ll_out', width: 4) <= a4.pow(b4);
    addOutput('pow_lc_out', width: 4) <= a4.pow(3);

    // ── Comparisons → $eq/$ne/$lt/$gt/$le/$ge ─────────────────────────
    addOutput('eq_ll_out') <= a4.eq(b4);
    addOutput('eq_lc_out') <= a4.eq(5);
    addOutput('neq_ll_out') <= a4.neq(b4);
    addOutput('neq_lc_out') <= a4.neq(5);
    addOutput('lt_ll_out') <= a4.lt(b4);
    addOutput('lt_lc_out') <= a4.lt(5);
    addOutput('gt_ll_out') <= (a4 > b4);
    addOutput('gt_lc_out') <= (a4 > 5);
    addOutput('le_ll_out') <= a4.lte(b4);
    addOutput('le_lc_out') <= a4.lte(5);
    addOutput('ge_ll_out') <= (a4 >= b4);
    addOutput('ge_lc_out') <= (a4 >= 5);

    // ── Shifts → $shl / $shr / $sshr (dynamic and constant amounts) ──
    addOutput('lshift_ll_out', width: 4) <= LShift(a4, shamt4).out;
    addOutput('lshift_lc_out', width: 4) <= LShift(a4, 2).out;
    addOutput('rshift_ll_out', width: 4) <= RShift(a4, shamt4).out;
    addOutput('rshift_lc_out', width: 4) <= RShift(a4, 2).out;
    addOutput('arshift_ll_out', width: 4) <= ARShift(a4, shamt4).out;
    addOutput('arshift_lc_out', width: 4) <= ARShift(a4, 2).out;

    // ── Mux / mux() ────────────────────────────────────────────────
    //
    // Dynamic control ⇒ a real `$mux` cell is instantiated.
    addOutput('mux_class_out', width: 4) <= Mux(muxSel, a4, b4).out;
    addOutput('mux_fn_dynamic_out', width: 4) <= mux(muxSel, a4, b4);

    // Constant, valid control ⇒ `mux()` folds to the selected input
    // directly at *build* time: no `$mux` cell is instantiated for these two
    // outputs at all. This documents/validates the function-level constant
    // fold described by `mux()`'s doc comment. These outputs are wired
    // directly to `a4`/`b4` (via a `$buf`-shaped netlist alias, if any) with
    // no arithmetic/select cell in between.
    addOutput('mux_fn_const1_out', width: 4) <= mux(Const(1, width: 1), a4, b4);
    addOutput('mux_fn_const0_out', width: 4) <= mux(Const(0, width: 1), a4, b4);

    // ── IndexGate → $shiftx (natural and oversized index widths) ─────
    addOutput('index_natural_out') <= a8[idx3];
    addOutput('index_oversized_out') <= a8[idx5];

    // ── ReplicationOp (retained as an explicit, unmapped cell; no
    // standard Yosys `$concat`/`$pos`-style cell models replication of a
    // single dynamic operand cleanly, so it is intentionally left visible
    // as its own `ReplicationOp`-typed cell rather than force-mapped) ────
    addOutput('replicate_x3_out', width: 12) <= a4.replicate(3);
    addOutput('replicate_x5_out', width: 20) <= a4.replicate(5);

    // ── BusSubset → $slice ────────────────────────────────────────────
    addOutput('slice_out', width: 4) <= a8.getRange(2, 6);

    // ── Swizzle → $concat ─────────────────────────────────────────────
    addOutput('swizzle_out', width: 8) <= [a4, b4].swizzle();

    // ── TriStateBuffer → $tribuf ───────────────────────────────────────
    TriStateBuffer(a8, enable: enableTri, name: 'tsb').out.gets(bus);
    addOutput('tribuf_readback_out', width: 8) <= bus;

    // ── FlipFlop variants → $dff/$dffe/$sdff/$sdffe/$adff/$adffe/
    //    $aldff/$aldffe, plus dynamic-synchronous-reset lowering ────────
    addOutput('q_dff', width: 4) <= flop(clk, d4);
    addOutput('q_dffe', width: 4) <= flop(clk, d4, en: en);
    addOutput('q_sdff', width: 4) <= flop(clk, d4, reset: reset, resetValue: 9);
    addOutput('q_sdffe', width: 4) <=
        flop(clk, d4, en: en, reset: reset, resetValue: 9);
    addOutput('q_adff', width: 4) <=
        flop(clk, d4, reset: reset, resetValue: 9, asyncReset: true);
    addOutput('q_adffe', width: 4) <=
        flop(clk, d4, en: en, reset: reset, resetValue: 9, asyncReset: true);
    addOutput('q_aldff', width: 4) <=
        flop(clk, d4,
            reset: reset, resetValue: resetValueDyn4, asyncReset: true);
    addOutput('q_aldffe', width: 4) <=
        flop(clk, d4,
            en: en, reset: reset, resetValue: resetValueDyn4, asyncReset: true);
    // Dynamic synchronous reset value: `$sdff`/`$sdffe` require a *constant*
    // reset value, so the netlist translator lowers these to a `$mux`
    // (selecting the reset value) feeding a plain `$dff`/`$dffe` (the enable
    // ORed with reset so reset retains priority when enabled).
    addOutput('q_dynsync_noen', width: 4) <=
        flop(clk, d4, reset: reset, resetValue: resetValueDyn4);
    addOutput('q_dynsync_en', width: 4) <=
        flop(clk, d4, en: en, reset: reset, resetValue: resetValueDyn4);
  }
}
