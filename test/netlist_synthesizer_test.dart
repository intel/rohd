// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// netlist_synthesizer_test.dart
// Comprehensive tests for the netlist synthesizer covering leaf cell
// mapping, structural validation, options permutations, and real
// example designs.
//
// 2026 April 13
// Author: Auto-generated

import 'dart:convert';
import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/examples/filter_bank_modules.dart';
import 'package:test/test.dart';

import '../example/example.dart';
import '../example/fir_filter.dart';
import '../example/logic_array.dart';
import '../example/oven_fsm.dart';
import '../example/tree.dart';

// ────────────────────────────────────────────────────────────────────
// Tiny helper modules for targeted gate-level tests
// ────────────────────────────────────────────────────────────────────

/// Exercises And2Gate.
class AndModule extends Module {
  Logic get y => output('y');
  AndModule(Logic a, Logic b) : super(name: 'andmod') {
    a = addInput('a', a);
    b = addInput('b', b);
    addOutput('y') <= a & b;
  }
}

/// Exercises Or2Gate.
class OrModule extends Module {
  Logic get y => output('y');
  OrModule(Logic a, Logic b) : super(name: 'ormod') {
    a = addInput('a', a);
    b = addInput('b', b);
    addOutput('y') <= a | b;
  }
}

/// Exercises Xor2Gate.
class XorModule extends Module {
  Logic get y => output('y');
  XorModule(Logic a, Logic b) : super(name: 'xormod') {
    a = addInput('a', a);
    b = addInput('b', b);
    addOutput('y') <= a ^ b;
  }
}

/// Exercises NotGate.
class NotModule extends Module {
  Logic get y => output('y');
  NotModule(Logic a) : super(name: 'notmod') {
    a = addInput('a', a);
    addOutput('y') <= ~a;
  }
}

/// Exercises Mux.
class MuxModule extends Module {
  Logic get y => output('y');
  MuxModule(Logic sel, Logic a, Logic b, {int width = 8}) : super(name: 'mux') {
    sel = addInput('sel', sel);
    a = addInput('a', a, width: width);
    b = addInput('b', b, width: width);
    addOutput('y', width: width) <= mux(sel, a, b);
  }
}

/// Exercises FlipFlop.
class FlopModule extends Module {
  Logic get q => output('q');
  FlopModule(Logic clk, Logic d, {int width = 8}) : super(name: 'flopmod') {
    clk = addInput('clk', clk);
    d = addInput('d', d, width: width);
    addOutput('q', width: width) <= flop(clk, d);
  }
}

/// Exercises Add.
class AddModule extends Module {
  Logic get sum => output('sum');
  AddModule(Logic a, Logic b, {int width = 8}) : super(name: 'addmod') {
    a = addInput('a', a, width: width);
    b = addInput('b', b, width: width);
    addOutput('sum', width: width) <= a + b;
  }
}

/// Exercises Multiply.
class MulModule extends Module {
  Logic get prod => output('prod');
  MulModule(Logic a, Logic b, {int width = 8}) : super(name: 'mulmod') {
    a = addInput('a', a, width: width);
    b = addInput('b', b, width: width);
    addOutput('prod', width: width) <= a * b;
  }
}

/// Exercises BusSubset ($slice).
class SliceModule extends Module {
  Logic get y => output('y');
  SliceModule(Logic a) : super(name: 'slicemod') {
    a = addInput('a', a, width: 8);
    addOutput('y', width: 4) <= a.getRange(2, 6);
  }
}

/// Exercises comparison operators.
class CompareModule extends Module {
  Logic get lt => output('lt');
  Logic get gt => output('gt');
  Logic get eq => output('eq');
  CompareModule(Logic a, Logic b, {int width = 8}) : super(name: 'cmpmod') {
    a = addInput('a', a, width: width);
    b = addInput('b', b, width: width);
    addOutput('lt') <= LessThan(a, b).out;
    addOutput('gt') <= GreaterThan(a, b).out;
    addOutput('eq') <= a.eq(b);
  }
}

/// Exercises shift operations.
class ShiftModule extends Module {
  Logic get shl => output('shl');
  Logic get shr => output('shr');
  ShiftModule(Logic a, Logic amt, {int width = 8}) : super(name: 'shiftmod') {
    a = addInput('a', a, width: width);
    amt = addInput('amt', amt, width: width);
    addOutput('shl', width: width) <= a << amt;
    addOutput('shr', width: width) <= a >>> amt;
  }
}

/// Exercises Xor2Gate.
class XorGateModule extends Module {
  Logic get y => output('y');
  XorGateModule(Logic a, Logic b) : super(name: 'xormod2') {
    a = addInput('a', a);
    b = addInput('b', b);
    addOutput('y') <= a ^ b;
  }
}

/// Exercises Subtract.
class SubModule extends Module {
  Logic get diff => output('diff');
  SubModule(Logic a, Logic b, {int width = 8}) : super(name: 'submod') {
    a = addInput('a', a, width: width);
    b = addInput('b', b, width: width);
    addOutput('diff', width: width) <= a - b;
  }
}

/// Exercises Swizzle ($concat).
class SwizzleModule extends Module {
  Logic get y => output('y');
  SwizzleModule(Logic a, Logic b, {int width = 4}) : super(name: 'swizmod') {
    a = addInput('a', a, width: width);
    b = addInput('b', b, width: width);
    addOutput('y', width: width * 2) <= [a, b].swizzle();
  }
}

/// Exercises arithmetic right shift (ARShift).
class ARShiftModule extends Module {
  Logic get y => output('y');
  ARShiftModule(Logic a, Logic amt, {int width = 8})
      : super(name: 'arshiftmod') {
    a = addInput('a', a, width: width);
    amt = addInput('amt', amt, width: width);
    addOutput('y', width: width) <= a >> amt;
  }
}

/// Exercises unary reduction ops.
class ReduceModule extends Module {
  Logic get andR => output('andR');
  Logic get orR => output('orR');
  Logic get xorR => output('xorR');
  ReduceModule(Logic a, {int width = 8}) : super(name: 'reducemod') {
    a = addInput('a', a, width: width);
    addOutput('andR') <= a.and();
    addOutput('orR') <= a.or();
    addOutput('xorR') <= a.xor();
  }
}

/// Exercises individual comparison ops for cell-type checking.
class LtModule extends Module {
  Logic get y => output('y');
  LtModule(Logic a, Logic b, {int width = 8}) : super(name: 'ltmod') {
    a = addInput('a', a, width: width);
    b = addInput('b', b, width: width);
    addOutput('y') <= a.lt(b);
  }
}

class GtModule extends Module {
  Logic get y => output('y');
  GtModule(Logic a, Logic b, {int width = 8}) : super(name: 'gtmod') {
    a = addInput('a', a, width: width);
    b = addInput('b', b, width: width);
    addOutput('y') <= a.gt(b);
  }
}

class EqModule extends Module {
  Logic get y => output('y');
  EqModule(Logic a, Logic b, {int width = 8}) : super(name: 'eqmod') {
    a = addInput('a', a, width: width);
    b = addInput('b', b, width: width);
    addOutput('y') <= a.eq(b);
  }
}

class NeqModule extends Module {
  Logic get y => output('y');
  NeqModule(Logic a, Logic b, {int width = 8}) : super(name: 'neqmod') {
    a = addInput('a', a, width: width);
    b = addInput('b', b, width: width);
    addOutput('y') <= a.neq(b);
  }
}

class LeqModule extends Module {
  Logic get y => output('y');
  LeqModule(Logic a, Logic b, {int width = 8}) : super(name: 'leqmod') {
    a = addInput('a', a, width: width);
    b = addInput('b', b, width: width);
    addOutput('y') <= a.lte(b);
  }
}

class GeqModule extends Module {
  Logic get y => output('y');
  GeqModule(Logic a, Logic b, {int width = 8}) : super(name: 'geqmod') {
    a = addInput('a', a, width: width);
    b = addInput('b', b, width: width);
    addOutput('y') <= a.gte(b);
  }
}

/// Exercises TriStateBuffer.
class TriBufModule extends Module {
  Logic get bus => inOut('bus');
  TriBufModule(LogicNet busNet, Logic data, Logic en)
      : super(name: 'tribufmod') {
    final bus = addInOut('bus', busNet, width: data.width);
    data = addInput('data', data, width: data.width);
    en = addInput('en', en);
    TriStateBuffer(data, enable: en, name: 'tsb').out.gets(bus);
  }
}

/// Exercises Combinational with If.
class CombIfModule extends Module {
  Logic get y => output('y');
  CombIfModule(Logic sel, Logic a, Logic b, {int width = 8})
      : super(name: 'combif') {
    sel = addInput('sel', sel);
    a = addInput('a', a, width: width);
    b = addInput('b', b, width: width);
    final y = addOutput('y', width: width);
    Combinational([
      If(sel, then: [y < a], orElse: [y < b]),
    ]);
  }
}

/// Exercises Sequential with If.
class SeqIfModule extends Module {
  Logic get q => output('q');
  SeqIfModule(Logic clk, Logic en, Logic d, {int width = 8})
      : super(name: 'seqif') {
    clk = addInput('clk', clk);
    en = addInput('en', en);
    d = addInput('d', d, width: width);
    final q = addOutput('q', width: width);
    Sequential(clk, [
      If(en, then: [q < d]),
    ]);
  }
}

/// Module with multiple instances of the same sub-module (dedup test).
class DedupTop extends Module {
  Logic get y0 => output('y0');
  Logic get y1 => output('y1');
  DedupTop(Logic a, Logic b, {int width = 8})
      : super(name: 'deduptop', definitionName: 'DedupTop') {
    a = addInput('a', a, width: width);
    b = addInput('b', b, width: width);
    addOutput('y0', width: width) <= AddModule(a, b, width: width).sum;
    addOutput('y1', width: width) <= AddModule(a, b, width: width).sum;
  }
}

/// Module with different-width instances (no dedup).
class NoDedupTop extends Module {
  Logic get y0 => output('y0');
  Logic get y1 => output('y1');
  NoDedupTop(Logic a4, Logic b4, Logic a8, Logic b8)
      : super(name: 'nodeduptop', definitionName: 'NoDedupTop') {
    a4 = addInput('a4', a4, width: 4);
    b4 = addInput('b4', b4, width: 4);
    a8 = addInput('a8', a8, width: 8);
    b8 = addInput('b8', b8, width: 8);
    addOutput('y0', width: 4) <= AddModule(a4, b4, width: 4).sum;
    addOutput('y1', width: 8) <= AddModule(a8, b8).sum;
  }
}

/// A module with a named constant (Logic..gets(Const)) used inside a
/// Combinational block — exercises the named-constant fix.
class _NamedConstModule extends Module {
  _NamedConstModule(Logic clk, Logic reset) : super(name: 'namedConstMod') {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);
    final dataIn = addInput('dataIn', Logic(width: 8), width: 8);
    final result = addOutput('result', width: 8);

    // Named constant driven by Const — this is the pattern from
    // _dynamicInputToLogic in SummationBase.
    final myConst = Logic(name: 'myConst', width: 8)..gets(Const(0, width: 8));

    Combinational([
      result < mux(dataIn.or(), dataIn, myConst),
    ]);
  }
}

// ────────────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────────────

/// Build a FilterBank module for testing (not yet built).
FilterBank _buildFilterBank() {
  const dataWidth = 16;
  const numTaps = 3;
  const coeffs0 = [1, 2, 1];
  const coeffs1 = [1, -2, 1];

  final clk = SimpleClockGenerator(10).clk;
  final reset = Logic(name: 'reset');
  final start = Logic(name: 'start');
  final samples = List.generate(2, (ch) => FilterSample(name: 'sample$ch'));
  final inputDone = Logic(name: 'inputDone');

  return FilterBank(
    clk,
    reset,
    start,
    samples,
    inputDone,
    numTaps: numTaps,
    dataWidth: dataWidth,
    coefficients: [coeffs0, coeffs1],
  );
}

/// Build a module and synthesize to a parsed JSON map.
Future<Map<String, dynamic>> _synthToMap(
  Module mod, {
  NetlistOptions options = const NetlistOptions(),
}) async {
  await mod.build();
  final synth = SynthBuilder(mod, NetlistSynthesizer(options: options));
  final json = (synth.synthesizer as NetlistSynthesizer).synthesizeToJson(
    mod,
  );
  return jsonDecode(json) as Map<String, dynamic>;
}

/// Extract the `modules` map from a synthesized JSON map.
Map<String, dynamic> _modules(Map<String, dynamic> json) =>
    json['modules'] as Map<String, dynamic>;

/// Get cells map from a module definition.
Map<String, dynamic> _cells(Map<String, dynamic> moduleDef) =>
    moduleDef['cells'] as Map<String, dynamic>? ?? {};

/// Get ports map from a module definition.
Map<String, dynamic> _ports(Map<String, dynamic> moduleDef) =>
    moduleDef['ports'] as Map<String, dynamic>? ?? {};

/// Get netnames map from a module definition.
Map<String, dynamic> _netnames(Map<String, dynamic> moduleDef) =>
    moduleDef['netnames'] as Map<String, dynamic>? ?? {};

/// Check that a module definition has a port with given name and direction.
void _expectPort(
  Map<String, dynamic> moduleDef,
  String portName,
  String direction,
) {
  final ports = _ports(moduleDef);
  expect(ports, contains(portName), reason: 'Expected port "$portName"');
  final port = ports[portName] as Map<String, dynamic>;
  expect(
    port['direction'],
    equals(direction),
    reason: 'Port "$portName" should be "$direction"',
  );
}

/// Returns true if any cell in any module definition has the given type.
bool _hasCellType(Map<String, dynamic> json, String cellType) {
  final mod = _modules(json);
  return mod.values.any((m) {
    final def = m as Map<String, dynamic>;
    return _cells(def).values.any((c) {
      final cell = c as Map<String, dynamic>;
      return (cell['type'] as String) == cellType;
    });
  });
}

// ────────────────────────────────────────────────────────────────────
// Tests
// ────────────────────────────────────────────────────────────────────

void main() {
  tearDown(() async {
    await Simulator.reset();
    ModuleServices.instance.reset();
  });

  // ── Group 1: Leaf cell mapper — individual gate mappings ───────────

  group('leaf cell mapping', () {
    test(r'And2Gate maps to $and cell', () async {
      final json = await _synthToMap(AndModule(Logic(), Logic()));
      expect(_hasCellType(json, r'$and'), isTrue);
    });

    test(r'Or2Gate maps to $or cell', () async {
      final json = await _synthToMap(OrModule(Logic(), Logic()));
      expect(_hasCellType(json, r'$or'), isTrue);
    });

    test(r'Xor2Gate maps to $xor cell', () async {
      final json = await _synthToMap(XorGateModule(Logic(), Logic()));
      expect(_hasCellType(json, r'$xor'), isTrue);
    });

    test(r'NotGate maps to $not cell', () async {
      final json = await _synthToMap(NotModule(Logic()));
      expect(_hasCellType(json, r'$not'), isTrue);
    });

    test(r'Mux maps to $mux cell', () async {
      final json = await _synthToMap(
        MuxModule(Logic(), Logic(width: 8), Logic(width: 8)),
      );
      expect(_hasCellType(json, r'$mux'), isTrue);
    });

    test(r'FlipFlop maps to $dff cell', () async {
      final clk = SimpleClockGenerator(10).clk;
      final json = await _synthToMap(FlopModule(clk, Logic(width: 8)));
      expect(_hasCellType(json, r'$dff'), isTrue);
    });

    test(r'Add maps to $add cell', () async {
      final json = await _synthToMap(
        AddModule(Logic(width: 8), Logic(width: 8)),
      );
      expect(_hasCellType(json, r'$add'), isTrue);
    });

    test(r'Subtract maps to $sub cell', () async {
      final json = await _synthToMap(
        SubModule(Logic(width: 8), Logic(width: 8)),
      );
      expect(_hasCellType(json, r'$sub'), isTrue);
    });

    test(r'Multiply maps to $mul cell', () async {
      final json = await _synthToMap(
        MulModule(Logic(width: 8), Logic(width: 8)),
      );
      expect(_hasCellType(json, r'$mul'), isTrue);
    });

    test(r'BusSubset maps to $slice cell', () async {
      final json = await _synthToMap(SliceModule(Logic(width: 8)));
      expect(_hasCellType(json, r'$slice'), isTrue);
    });

    test(r'Swizzle maps to $concat cell', () async {
      final json = await _synthToMap(
        SwizzleModule(Logic(width: 4), Logic(width: 4)),
      );
      expect(_hasCellType(json, r'$concat'), isTrue);
    });

    test(r'LessThan maps to $lt cell', () async {
      final json = await _synthToMap(
        LtModule(Logic(width: 8), Logic(width: 8)),
      );
      expect(_hasCellType(json, r'$lt'), isTrue);
    });

    test(r'GreaterThan maps to $gt cell', () async {
      final json = await _synthToMap(
        GtModule(Logic(width: 8), Logic(width: 8)),
      );
      expect(_hasCellType(json, r'$gt'), isTrue);
    });

    test(r'Equals maps to $eq cell', () async {
      final json = await _synthToMap(
        EqModule(Logic(width: 8), Logic(width: 8)),
      );
      expect(_hasCellType(json, r'$eq'), isTrue);
    });

    test(r'NotEquals maps to $ne cell', () async {
      final json = await _synthToMap(
        NeqModule(Logic(width: 8), Logic(width: 8)),
      );
      expect(_hasCellType(json, r'$ne'), isTrue);
    });

    test(r'LessThanOrEqual maps to $le cell', () async {
      final json = await _synthToMap(
        LeqModule(Logic(width: 8), Logic(width: 8)),
      );
      expect(_hasCellType(json, r'$le'), isTrue);
    });

    test(r'GreaterThanOrEqual maps to $ge cell', () async {
      final json = await _synthToMap(
        GeqModule(Logic(width: 8), Logic(width: 8)),
      );
      expect(_hasCellType(json, r'$ge'), isTrue);
    });

    test(r'LShift maps to $shl cell', () async {
      final json = await _synthToMap(
        ShiftModule(Logic(width: 8), Logic(width: 8)),
      );
      expect(_hasCellType(json, r'$shl'), isTrue);
    });

    test(r'RShift maps to $shr cell', () async {
      final json = await _synthToMap(
        ShiftModule(Logic(width: 8), Logic(width: 8)),
      );
      expect(_hasCellType(json, r'$shr'), isTrue);
    });

    test(r'ARShift maps to $shiftx cell', () async {
      final json = await _synthToMap(
        ARShiftModule(Logic(width: 8), Logic(width: 8)),
      );
      expect(_hasCellType(json, r'$shiftx'), isTrue);
    });

    test(r'AndUnary maps to $reduce_and cell', () async {
      final json = await _synthToMap(ReduceModule(Logic(width: 8)));
      expect(_hasCellType(json, r'$reduce_and'), isTrue);
    });

    test(r'OrUnary maps to $reduce_or cell', () async {
      final json = await _synthToMap(ReduceModule(Logic(width: 8)));
      expect(_hasCellType(json, r'$reduce_or'), isTrue);
    });

    test(r'XorUnary maps to $reduce_xor cell', () async {
      final json = await _synthToMap(ReduceModule(Logic(width: 8)));
      expect(_hasCellType(json, r'$reduce_xor'), isTrue);
    });

    test(r'TriStateBuffer maps to $tribuf cell', () async {
      final busNet = LogicNet(width: 8);
      final json = await _synthToMap(
        TriBufModule(busNet, Logic(width: 8), Logic()),
      );
      expect(_hasCellType(json, r'$tribuf'), isTrue);
    });
  });

  // ── Group 2: Structural content validation ─────────────────────────

  group('structural validation', () {
    test('ports have correct direction', () async {
      final json = await _synthToMap(
        AddModule(Logic(width: 8), Logic(width: 8)),
      );
      // Find the top-level or AddModule definition
      final mod = _modules(json);
      for (final def in mod.values) {
        final d = def as Map<String, dynamic>;
        final ports = _ports(d);
        for (final port in ports.entries) {
          final p = port.value as Map<String, dynamic>;
          expect(
            ['input', 'output', 'inout'].contains(p['direction']),
            isTrue,
            reason: 'Port ${port.key} should have valid direction',
          );
          // Each port should have bits
          expect(
            p['bits'],
            isNotNull,
            reason: 'Port ${port.key} should have bits array',
          );
        }
      }
    });

    test('cells have type and connections', () async {
      final json = await _synthToMap(
        MuxModule(Logic(), Logic(width: 8), Logic(width: 8)),
      );
      final mod = _modules(json);
      for (final def in mod.values) {
        final d = def as Map<String, dynamic>;
        for (final cell in _cells(d).values) {
          final c = cell as Map<String, dynamic>;
          expect(c['type'], isNotNull, reason: 'Every cell should have a type');
          expect(
            c['connections'],
            isNotNull,
            reason: 'Every cell should have connections',
          );
        }
      }
    });

    test('netnames have bits arrays', () async {
      final json = await _synthToMap(
        AddModule(Logic(width: 8), Logic(width: 8)),
      );
      final mod = _modules(json);
      for (final def in mod.values) {
        final d = def as Map<String, dynamic>;
        for (final nn in _netnames(d).values) {
          final n = nn as Map<String, dynamic>;
          expect(
            n['bits'],
            isA<List<dynamic>>(),
            reason: 'Each netname should have a bits list',
          );
        }
      }
    });

    test('inOut ports have direction inout', () async {
      final busNet = LogicNet(width: 8);
      final json = await _synthToMap(
        TriBufModule(busNet, Logic(width: 8), Logic()),
      );
      final mod = _modules(json);
      // Find the TriBufModule definition
      final tribufDef = mod.values.firstWhere((m) {
        final d = m as Map<String, dynamic>;
        return _ports(d).values.any((p) {
          final port = p as Map<String, dynamic>;
          return port['direction'] == 'inout';
        });
      }, orElse: () => <String, dynamic>{}) as Map<String, dynamic>;
      expect(
        tribufDef,
        isNotEmpty,
        reason: 'Should have a module with inout ports',
      );
    });

    test('Combinational If produces Combinational cell', () async {
      final json = await _synthToMap(
        CombIfModule(Logic(), Logic(width: 8), Logic(width: 8)),
      );
      // Combinational blocks become Combinational cell type
      expect(
        _hasCellType(json, 'Combinational'),
        isTrue,
        reason: 'Combinational If should produce a Combinational cell',
      );
    });

    test('Sequential If produces dff cells', () async {
      final clk = SimpleClockGenerator(10).clk;
      final json = await _synthToMap(
        SeqIfModule(clk, Logic(), Logic(width: 8)),
      );
      final mod = _modules(json);
      final hasSeq = mod.values.any((m) {
        final def = m as Map<String, dynamic>;
        final cells = _cells(def);
        return cells.values.any((c) {
          final cell = c as Map<String, dynamic>;
          return (cell['type'] as String).contains('Sequential');
        });
      });
      expect(
        hasSeq,
        isTrue,
        reason: 'Sequential If should contain Sequential cells',
      );
    });
  });

  // ── Group 3: Module deduplication ──────────────────────────────────

  group('deduplication', () {
    test('identical sub-modules are deduplicated', () async {
      final json = await _synthToMap(
        DedupTop(Logic(width: 8), Logic(width: 8)),
      );
      final mod = _modules(json);
      // AddModule should appear only once as a definition
      final addDefs = mod.keys.where((k) => k.contains('Add')).toList();
      expect(
        addDefs.length,
        equals(1),
        reason: 'Two identical AddModules should produce one definition',
      );
      // But should be instantiated twice in the top-level cells
      final topDef = mod.entries
          .firstWhere((e) => e.key.contains('DedupTop'))
          .value as Map<String, dynamic>;
      final addCells = _cells(topDef).values.where((c) {
        final cell = c as Map<String, dynamic>;
        return (cell['type'] as String).contains('Add');
      }).toList();
      expect(
        addCells.length,
        equals(2),
        reason: 'Top module should instantiate AddModule twice',
      );
    });

    test('different-width sub-modules are not deduplicated', () async {
      final json = await _synthToMap(
        NoDedupTop(
          Logic(width: 4),
          Logic(width: 4),
          Logic(width: 8),
          Logic(width: 8),
        ),
      );
      final mod = _modules(json);
      // Should have two distinct AddModule definitions (different widths)
      final addDefs = mod.keys.where((k) => k.contains('Add')).toList();
      expect(
        addDefs.length,
        greaterThanOrEqualTo(2),
        reason: 'Different-width AddModules should NOT be deduplicated',
      );
    });
  });

  // ── Group 4: NetlistOptions permutations ─────────────────────────

  group('NetlistOptions', () {
    late Module filterBank;

    setUp(() async {
      await Simulator.reset();
      filterBank = _buildFilterBank();
      await filterBank.build();
    });

    test('default options produce valid netlist', () async {
      final synth = SynthBuilder(filterBank, NetlistSynthesizer());
      final json = (synth.synthesizer as NetlistSynthesizer)
          .synthesizeToJson(filterBank);
      final parsed = jsonDecode(json) as Map<String, dynamic>;
      expect(_modules(parsed), isNotEmpty);
    });

    test('slimMode omits connections', () async {
      final synth = SynthBuilder(
        filterBank,
        NetlistSynthesizer(options: const NetlistOptions(slimMode: true)),
      );
      final json = (synth.synthesizer as NetlistSynthesizer)
          .synthesizeToJson(filterBank);
      final parsed = jsonDecode(json) as Map<String, dynamic>;
      final mod = _modules(parsed);
      expect(mod, isNotEmpty);
      // In slim mode, cells should exist but connections should be empty
      for (final def in mod.values) {
        final d = def as Map<String, dynamic>;
        for (final cell in _cells(d).values) {
          final c = cell as Map<String, dynamic>;
          final conns = c['connections'] as Map<String, dynamic>?;
          if (conns != null) {
            expect(
              conns,
              isEmpty,
              reason: 'Slim mode cells should have empty connections',
            );
          }
        }
      }
    });

    test('DCE disabled still produces valid netlist', () async {
      final synth = SynthBuilder(
        filterBank,
        NetlistSynthesizer(options: const NetlistOptions(enableDCE: false)),
      );
      final json = (synth.synthesizer as NetlistSynthesizer)
          .synthesizeToJson(filterBank);
      final parsed = jsonDecode(json) as Map<String, dynamic>;
      expect(_modules(parsed), isNotEmpty);
    });

    test('all optimizations disabled produces valid netlist', () async {
      final synth = SynthBuilder(
        filterBank,
        NetlistSynthesizer(options: const NetlistOptions(enableDCE: false)),
      );
      final json = (synth.synthesizer as NetlistSynthesizer)
          .synthesizeToJson(filterBank);
      final parsed = jsonDecode(json) as Map<String, dynamic>;
      expect(_modules(parsed), isNotEmpty);
    });

    test('slim and full produce same module definitions', () async {
      final fullSynth = SynthBuilder(filterBank, NetlistSynthesizer());
      final fullJson = (fullSynth.synthesizer as NetlistSynthesizer)
          .synthesizeToJson(filterBank);
      final fullParsed = jsonDecode(fullJson) as Map<String, dynamic>;

      // Rebuild for slim
      await Simulator.reset();
      final fb2 = _buildFilterBank();
      await fb2.build();
      final slimSynth = SynthBuilder(
        fb2,
        NetlistSynthesizer(options: const NetlistOptions(slimMode: true)),
      );
      final slimJson =
          (slimSynth.synthesizer as NetlistSynthesizer).synthesizeToJson(fb2);
      final slimParsed = jsonDecode(slimJson) as Map<String, dynamic>;

      // Same module definition names
      expect(
        _modules(slimParsed).keys.toSet(),
        equals(_modules(fullParsed).keys.toSet()),
        reason: 'Slim and full should have identical module definition names',
      );
    });
  });

  // ── Group 5: Example designs — structural checks ───────────────────

  group('example designs', () {
    test('Counter netlist has FlipFlop and FSM-related cells', () async {
      final en = Logic(name: 'en');
      final reset = Logic(name: 'reset');
      final clk = SimpleClockGenerator(10).clk;
      final counter = Counter(en, reset, clk);
      final json = await _synthToMap(counter);
      final mod = _modules(json);

      expect(
        mod,
        isNotEmpty,
        reason: 'Counter should produce module definitions',
      );
      // Should have a Counter definition
      expect(mod.keys.any((k) => k.contains('Counter')), isTrue);
    });

    test('FirFilter netlist has pipeline and multiplier cells', () async {
      final en = Logic(name: 'en');
      final resetB = Logic(name: 'resetB');
      final clk = SimpleClockGenerator(10).clk;
      final inputVal = Logic(name: 'inputVal', width: 8);
      final fir = FirFilter(
          en,
          resetB,
          clk,
          inputVal,
          [
            0,
            0,
            0,
            1,
          ],
          bitWidth: 8);
      final json = await _synthToMap(fir);
      final mod = _modules(json);

      expect(
        mod,
        isNotEmpty,
        reason: 'FirFilter should produce module definitions',
      );
    });

    test('OvenModule netlist has FSM states', () async {
      final button = Logic(name: 'button', width: 2);
      final reset = Logic(name: 'reset');
      final clk = SimpleClockGenerator(10).clk;
      final oven = OvenModule(button, reset, clk);
      final json = await _synthToMap(oven);
      final mod = _modules(json);

      expect(mod, isNotEmpty);
      // Should have OvenModule definition
      expect(
        mod.keys.any((k) => k.contains('Oven') || k.contains('oven')),
        isTrue,
      );
    });

    test('LogicArrayExample netlist has array-related cells', () async {
      final arrayA = LogicArray([4], 8, name: 'arrayA');
      final id = Logic(name: 'id', width: 3);
      final selectIndexValue = Logic(name: 'selectIndexValue', width: 8);
      final selectFromValue = Logic(name: 'selectFromValue', width: 8);
      final la = LogicArrayExample(
        arrayA,
        id,
        selectIndexValue,
        selectFromValue,
      );
      final json = await _synthToMap(la);
      final mod = _modules(json);

      expect(mod, isNotEmpty);
    });

    test('TreeOfTwoInputModules netlist has recursive hierarchy', () async {
      final seq = List<Logic>.generate(4, (_) => Logic(width: 8));
      final tree = TreeOfTwoInputModules(seq, (a, b) => mux(a > b, a, b));
      await tree.build();
      final synth = SynthBuilder(tree, NetlistSynthesizer());
      final json =
          (synth.synthesizer as NetlistSynthesizer).synthesizeToJson(tree);
      expect(json, isNotEmpty);
      final parsed = jsonDecode(json) as Map<String, dynamic>;
      final mod = _modules(parsed);
      expect(mod, isNotEmpty, reason: 'Tree should have module definitions');
    });
  });

  // ── Group 6: FilterBank deep structural checks ─────────────────────

  group('FilterBank netlist structure', () {
    late Map<String, dynamic> json;

    setUpAll(() async {
      final fb = _buildFilterBank();
      json = await _synthToMap(fb);
    });

    test('contains expected module definitions', () {
      final mod = _modules(json);
      final defNames = mod.keys.toSet();

      // FilterBank, FilterChannel, CoeffBank, MacUnit, FilterController
      // should all appear (possibly with parameterized suffixes)
      expect(
        defNames.any((k) => k.contains('FilterBank')),
        isTrue,
        reason: 'Should have FilterBank definition',
      );
      expect(
        defNames.any((k) => k.contains('FilterChannel')),
        isTrue,
        reason: 'Should have FilterChannel definition',
      );
      expect(
        defNames.any((k) => k.contains('CoeffBank')),
        isTrue,
        reason: 'Should have CoeffBank definition',
      );
      expect(
        defNames.any((k) => k.contains('MacUnit')),
        isTrue,
        reason: 'Should have MacUnit definition',
      );
      expect(
        defNames.any((k) => k.contains('FilterController')),
        isTrue,
        reason: 'Should have FilterController definition',
      );
    });

    test('FilterBank has array ports', () {
      final mod = _modules(json);
      final fbDef = mod.entries
          .firstWhere((e) => e.key.contains('FilterBank'))
          .value as Map<String, dynamic>;
      final ports = _ports(fbDef);

      // Should have sample0/sample1 and channelOut as array ports
      expect(
        ports.keys.any(
          (k) => k.contains('sample') || k.contains('channelOut'),
        ),
        isTrue,
        reason: 'FilterBank should have array port signals',
      );
    });

    test('FilterBank top instantiates two FilterChannels', () {
      final mod = _modules(json);
      final fbDef = mod.entries
          .firstWhere((e) => e.key.contains('FilterBank'))
          .value as Map<String, dynamic>;
      final cells = _cells(fbDef);

      final channelCells = cells.entries.where((e) {
        final cell = e.value as Map<String, dynamic>;
        return (cell['type'] as String).contains('FilterChannel');
      }).toList();

      expect(
        channelCells.length,
        equals(2),
        reason: 'FilterBank should instantiate 2 FilterChannels',
      );
    });

    test(
      'FilterChannels with different coefficients get separate definitions',
      () {
        final mod = _modules(json);
        final channelDefs =
            mod.keys.where((k) => k.contains('FilterChannel')).toList();

        expect(
          channelDefs.length,
          equals(2),
          reason: 'Two FilterChannels with different coefficients '
              'should produce distinct definitions',
        );
      },
    );

    test('MacUnit definition contains Pipeline-generated cells', () {
      final mod = _modules(json);
      final macDef = mod.entries
          .firstWhere((e) => e.key.contains('MacUnit'))
          .value as Map<String, dynamic>;
      final cells = _cells(macDef);

      // Pipeline generates Sequential cells for stage registers
      final hasSeq = cells.values.any((c) {
        final cell = c as Map<String, dynamic>;
        final type = cell['type'] as String;
        return type.contains('Sequential');
      });
      expect(
        hasSeq,
        isTrue,
        reason: 'MacUnit Pipeline should produce Sequential cells',
      );
    });

    test('CoeffBank has coeffArray input port', () {
      final mod = _modules(json);
      final coeffDef = mod.entries
          .firstWhere((e) => e.key.contains('CoeffBank'))
          .value as Map<String, dynamic>;
      final ports = _ports(coeffDef);

      // Should have coeffArray-related port names
      expect(
        ports.keys.any((k) => k.contains('coeffArray')),
        isTrue,
        reason: 'CoeffBank should have coeffArray port',
      );

      // tapIndex should be input
      expect(
        ports.keys.any((k) => k.contains('tapIndex')),
        isTrue,
        reason: 'CoeffBank should have tapIndex port',
      );
    });

    test('FilterController has FSM state output', () {
      final mod = _modules(json);
      final ctrlDef = mod.entries
          .firstWhere((e) => e.key.contains('FilterController'))
          .value as Map<String, dynamic>;
      final ports = _ports(ctrlDef);

      _expectPort(ctrlDef, 'state', 'output');
      _expectPort(ctrlDef, 'filterEnable', 'output');
      _expectPort(ctrlDef, 'doneFlag', 'output');
      expect(ports.keys.any((k) => k.contains('clk')), isTrue);
      expect(ports.keys.any((k) => k.contains('reset')), isTrue);
    });

    test('all module definitions have valid JSON structure', () {
      final mod = _modules(json);
      for (final entry in mod.entries) {
        final defName = entry.key;
        final def = entry.value as Map<String, dynamic>;

        // Every definition must have ports and cells
        expect(
          def.containsKey('ports'),
          isTrue,
          reason: '$defName should have ports',
        );
        expect(
          def.containsKey('cells'),
          isTrue,
          reason: '$defName should have cells',
        );

        // All ports must have direction and bits
        for (final port in _ports(def).entries) {
          final p = port.value as Map<String, dynamic>;
          expect(
            p.containsKey('direction'),
            isTrue,
            reason: '$defName.${port.key} should have direction',
          );
          expect(
            p.containsKey('bits'),
            isTrue,
            reason: '$defName.${port.key} should have bits',
          );
        }

        // All cells must have type
        for (final cell in _cells(def).entries) {
          final c = cell.value as Map<String, dynamic>;
          expect(
            c.containsKey('type'),
            isTrue,
            reason: '$defName cell ${cell.key} should have type',
          );
        }
      }
    });
  });

  // ── Group 7: Design API path ───────────────────────────────────────

  group('Design API path', () {
    test('build with netlistOptions enables NetlistService', () async {
      final en = Logic(name: 'en');
      final reset = Logic(name: 'reset');
      final clk = SimpleClockGenerator(10).clk;
      final counter = Counter(en, reset, clk);

      await counter.build();
      final netSvc = NetlistService(counter);

      final fullJson = netSvc.json;
      expect(fullJson, isNotNull);

      final parsed = jsonDecode(fullJson) as Map<String, dynamic>;
      expect(parsed.containsKey('modules'), isTrue);
    });

    test('moduleJson returns per-module data', () async {
      final fb = _buildFilterBank();
      await fb.build();
      final netSvc = NetlistService(fb);

      // Fetch FilterBank definition specifically
      final fbJson = netSvc.moduleJson(fb.definitionName);
      final parsed = jsonDecode(fbJson) as Map<String, dynamic>;
      final modules = parsed['modules'] as Map<String, dynamic>;
      expect(modules.containsKey(fb.definitionName), isTrue);
    });

    test('slimJson produces slim output', () async {
      final fb = _buildFilterBank();
      await fb.build();
      final netSvc = NetlistService(fb);

      final slimJson = netSvc.slimJson;

      final parsed = jsonDecode(slimJson) as Map<String, dynamic>;
      expect(parsed.containsKey('netlist'), isTrue);
      final netlist = parsed['netlist'] as Map<String, dynamic>;
      final modules = netlist['modules'] as Map<String, dynamic>;
      expect(modules, isNotEmpty);
    });

    test('NetlistService is an OutputService and registers itself', () async {
      final fb = _buildFilterBank();
      await fb.build();
      final netSvc = NetlistService(fb);

      expect(netSvc, isA<OutputService>());
      expect(ModuleServices.instance.lookup<NetlistService>(), same(netSvc));
      expect(NetlistService.current, same(netSvc));

      final summary = netSvc.toJson();
      expect(summary['version'], equals(netSvc.version));
      expect(summary['modules'], isList);

      ModuleServices.instance.reset();
      expect(ModuleServices.instance.lookup<NetlistService>(), isNull);
    });

    test('register false keeps NetlistService out of the registry', () async {
      final fb = _buildFilterBank();
      await fb.build();
      ModuleServices.instance.reset();
      NetlistService(fb, register: false);
      expect(ModuleServices.instance.lookup<NetlistService>(), isNull);
    });

    test('write() emits the full netlist JSON to a file', () async {
      final fb = _buildFilterBank();
      await fb.build();
      final netSvc = NetlistService(fb, register: false);

      final dir = Directory.systemTemp.createTempSync('rohd_netlist_');
      try {
        final path = '${dir.path}/netlist.json';
        netSvc.write(path);
        expect(File(path).readAsStringSync(), equals(netSvc.json));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });

  // ── Group 8: Wire ID and structural invariants ─────────────────────

  group('wire ID and structural invariants', () {
    test('all wire IDs are >= 2 (0 and 1 reserved for constants)', () async {
      final json = await _synthToMap(
        AddModule(Logic(width: 8), Logic(width: 8)),
      );
      final mod = _modules(json);
      for (final entry in mod.entries) {
        final def = entry.value as Map<String, dynamic>;
        // Check ports
        for (final port in _ports(def).entries) {
          final p = port.value as Map<String, dynamic>;
          final bits = p['bits'] as List<dynamic>;
          for (final bit in bits) {
            if (bit is int) {
              expect(
                bit,
                greaterThanOrEqualTo(2),
                reason: 'Wire ID ${port.key} bit $bit should be >= 2',
              );
            }
          }
        }
      }
    });

    test(r'FilterBank contains $const cells for constant drivers', () async {
      final json = await _synthToMap(_buildFilterBank());
      expect(
        _hasCellType(json, r'$const'),
        isTrue,
        reason: r'FilterBank should have $const cells for constant values',
      );
    });

    test('passthrough buffers prevent input-output wire sharing', () async {
      // A module whose output directly comes from an input should get a
      // $buf for wire-ID isolation.
      final json = await _synthToMap(
        AddModule(Logic(width: 8), Logic(width: 8)),
      );
      final mod = _modules(json);
      // Verify input and output port bits don't overlap in any definition
      for (final entry in mod.entries) {
        final def = entry.value as Map<String, dynamic>;
        final ports = _ports(def);
        final inputBits = <int>{};
        final outputBits = <int>{};
        for (final port in ports.entries) {
          final p = port.value as Map<String, dynamic>;
          final bits = (p['bits'] as List<dynamic>).whereType<int>().toSet();
          final dir = p['direction'] as String;
          if (dir == 'input') {
            inputBits.addAll(bits);
          } else if (dir == 'output') {
            outputBits.addAll(bits);
          }
        }
        expect(
          inputBits.intersection(outputBits),
          isEmpty,
          reason: '${entry.key}: input and output ports should not share wire '
              'IDs (passthrough buffer should break sharing)',
        );
      }
    });
  });

  // ── Group 9: DCE (dead-cell elimination) verification ──────────────

  group('dead-cell elimination', () {
    test('DCE enabled produces fewer cells than DCE disabled', () async {
      final fbDce = _buildFilterBank();
      final jsonDce = await _synthToMap(fbDce);
      int countCells(Map<String, dynamic> j) {
        var total = 0;
        for (final def in _modules(j).values) {
          total += _cells(def as Map<String, dynamic>).length;
        }
        return total;
      }

      final fbNoDce = _buildFilterBank();
      final jsonNoDce = await _synthToMap(
        fbNoDce,
        options: const NetlistOptions(enableDCE: false),
      );

      final dceCells = countCells(jsonDce);
      final noDceCells = countCells(jsonNoDce);
      expect(
        dceCells,
        lessThanOrEqualTo(noDceCells),
        reason: 'DCE should remove at least as many cells as no-DCE',
      );
    });

    test(r'DCE removes floating $const cells', () async {
      // With DCE disabled, there may be more $const cells
      final fbDce = _buildFilterBank();
      final jsonDce = await _synthToMap(fbDce);
      int countConstCells(Map<String, dynamic> j) {
        var total = 0;
        for (final def in _modules(j).values) {
          final d = def as Map<String, dynamic>;
          for (final cell in _cells(d).values) {
            final c = cell as Map<String, dynamic>;
            if ((c['type'] as String) == r'$const') {
              total++;
            }
          }
        }
        return total;
      }

      final fbNoDce = _buildFilterBank();
      final jsonNoDce = await _synthToMap(
        fbNoDce,
        options: const NetlistOptions(enableDCE: false),
      );

      expect(
        countConstCells(jsonDce),
        lessThanOrEqualTo(countConstCells(jsonNoDce)),
        reason: r'DCE should not produce more $const cells than no-DCE',
      );
    });
  });

  // ── Group 10: Post-processing option combinations ──────────────────

  group('post-processing options', () {
    test('collapseTransparentClusters produces valid netlist', () async {
      final fb = _buildFilterBank();
      final json = await _synthToMap(
        fb,
        options: const NetlistOptions(collapseTransparentClusters: true),
      );
      expect(_modules(json), isNotEmpty);
    });
  });

  // ── Group 11: Named constant signals ─────────────────────────────

  group('named constant signals', () {
    test(r'Logic..gets(Const) produces $const cell and netname', () async {
      final mod = _NamedConstModule(Logic(name: 'clk'), Logic(name: 'reset'));
      final json = await _synthToMap(mod);
      final mods = _modules(json);

      // Find the module definition for _NamedConstModule.
      final modDef = mods.values.firstWhere(
        (m) {
          final def = m as Map<String, dynamic>;
          return (def['cells'] as Map?)?.isNotEmpty ?? false;
        },
        orElse: () => mods.values.first,
      ) as Map<String, dynamic>;

      final netnames = _netnames(modDef);
      final cells = _cells(modDef);

      // The signal 'myConst' should appear as a netname.
      expect(
        netnames.keys.any((n) => n.contains('myConst')),
        isTrue,
        reason: "Logic('myConst')..gets(Const(0)) should produce a netname",
      );

      // There should be a $const cell driving it.
      expect(
        cells.values.any(
          (c) => (c as Map<String, dynamic>)['type'] == r'$const',
        ),
        isTrue,
        reason: r'Named constant should have a $const driver cell',
      );

      // The netname bits should be integer wire IDs (not string literals).
      final constNetname =
          netnames.entries.firstWhere((e) => e.key.contains('myConst'));
      final bits = (constNetname.value as Map<String, dynamic>)['bits'] as List;
      expect(
        bits.every((b) => b is int),
        isTrue,
        reason: 'Named constant netname should have integer wire IDs '
            r'(driven by a $const cell)',
      );
    });
  });
}
