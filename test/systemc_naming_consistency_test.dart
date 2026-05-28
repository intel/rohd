// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemc_naming_consistency_test.dart
// Validates that the SystemC synthesizer produces signal names consistent
// with the SystemVerilog synthesizer via the shared Module.namer.
//
// 2026 May
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/systemc/systemc_synth_module_definition.dart';
import 'package:rohd/src/synthesizers/systemc/systemc_synthesis_result.dart';
import 'package:rohd/src/synthesizers/systemverilog/systemverilog_synth_module_definition.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';
import 'package:test/test.dart';

// ── Helper modules ──────────────────────────────────────────────────

/// Simple combinational logic with an inner sub-module.
class _Inner extends Module {
  _Inner(Logic a, Logic b) : super(name: 'inner') {
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);
    addOutput('y', width: a.width) <= a & b;
  }
}

class _Outer extends Module {
  _Outer(Logic a, Logic b) : super(name: 'outer') {
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);
    final inner = _Inner(a, b);
    addOutput('y', width: a.width) <= inner.output('y');
  }
}

/// A module with a constant assignment.
class _ConstModule extends Module {
  _ConstModule(Logic a) : super(name: 'constmod') {
    a = addInput('a', a, width: 8);
    final c = Const(0x42, width: 8).named('myConst', naming: Naming.mergeable);
    addOutput('y', width: 8) <= a + c;
  }
}

/// A module with mixed naming priorities.
class _MixedNaming extends Module {
  _MixedNaming(Logic a) : super(name: 'mixednaming') {
    a = addInput('a', a, width: 8);
    final r = Logic(name: 'renamed', width: 8, naming: Naming.renameable)
      ..gets(a);
    final m = Logic(name: 'merged', width: 8, naming: Naming.mergeable)
      ..gets(r);
    addOutput('y', width: 8) <= m;
  }
}

/// A module with a FlipFlop (exercises Sequential/clocked naming).
class _FlopModule extends Module {
  _FlopModule(Logic clk, Logic d) : super(name: 'flopmod') {
    clk = addInput('clk', clk);
    d = addInput('d', d, width: 8);
    addOutput('q', width: 8) <= flop(clk, d);
  }
}

/// A module with a Combinational block.
class _CombModule extends Module {
  _CombModule(Logic a, Logic b) : super(name: 'combmod') {
    a = addInput('a', a, width: 8);
    b = addInput('b', b, width: 8);
    final out = addOutput('y', width: 8);
    Combinational([
      If(a.eq(b), then: [out < a], orElse: [out < b]),
    ]);
  }
}

/// A module with multiple internal signals that may collide.
class _CollisionModule extends Module {
  _CollisionModule(Logic a) : super(name: 'collision') {
    a = addInput('a', a, width: 8);
    final x = Logic(name: 'sig', width: 8)..gets(a);
    final y = Logic(name: 'sig', width: 8)..gets(x);
    addOutput('out', width: 8) <= y;
  }
}

// ── Utilities ────────────────────────────────────────────────────────

/// Collects Logic→name mappings from a SynthModuleDefinition for all
/// signals that have had their names picked (alive, not pruned/replaced).
Map<Logic, String> _collectNames(SynthModuleDefinition def) {
  final names = <Logic, String>{};
  for (final sl in [
    ...def.inputs,
    ...def.outputs,
    ...def.inOuts,
    ...def.internalSignals,
  ]) {
    try {
      final n = sl.name;
      for (final logic in sl.logics) {
        names[logic] = n;
      }
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      // name not picked — skip (replaced/pruned signal)
    }
  }
  return names;
}

/// Verifies that all signals present in both maps have the same name.
void _expectConsistentNames(
  Map<Logic, String> svNames,
  Map<Logic, String> scNames, {
  required String context,
}) {
  for (final logic in svNames.keys) {
    if (scNames.containsKey(logic)) {
      expect(scNames[logic], svNames[logic],
          reason: '$context: Name mismatch for Logic "${logic.name}" '
              '(${logic.runtimeType}, naming=${logic.naming}). '
              'SV="${svNames[logic]}", SC="${scNames[logic]}"');
    }
  }
}

// ── Tests ────────────────────────────────────────────────────────────

void main() {
  group('SystemC vs SystemVerilog naming consistency', () {
    test('simple hierarchy - port and internal signal names match', () async {
      final mod = _Outer(Logic(width: 8), Logic(width: 8));
      await mod.build();

      final svDef = SystemVerilogSynthModuleDefinition(mod);
      final scDef = SystemCSynthModuleDefinition(mod);

      final svNames = _collectNames(svDef);
      final scNames = _collectNames(scDef);

      _expectConsistentNames(svNames, scNames, context: '_Outer');

      // Port names must be present in both.
      for (final port in [...mod.inputs.values, ...mod.outputs.values]) {
        expect(svNames[port], isNotNull,
            reason: 'SV should have port ${port.name}');
        expect(scNames[port], isNotNull,
            reason: 'SC should have port ${port.name}');
        expect(scNames[port], svNames[port],
            reason: 'Port "${port.name}" must match between SV and SC');
      }
    });

    test('constant module - names match', () async {
      final mod = _ConstModule(Logic(width: 8));
      await mod.build();

      final svDef = SystemVerilogSynthModuleDefinition(mod);
      final scDef = SystemCSynthModuleDefinition(mod);

      _expectConsistentNames(
        _collectNames(svDef),
        _collectNames(scDef),
        context: '_ConstModule',
      );
    });

    test('mixed naming priorities - names match', () async {
      final mod = _MixedNaming(Logic(width: 8));
      await mod.build();

      final svDef = SystemVerilogSynthModuleDefinition(mod);
      final scDef = SystemCSynthModuleDefinition(mod);

      _expectConsistentNames(
        _collectNames(svDef),
        _collectNames(scDef),
        context: '_MixedNaming',
      );
    });

    test('flop module - clocked signal names match', () async {
      final mod = _FlopModule(Logic(), Logic(width: 8));
      await mod.build();

      final svDef = SystemVerilogSynthModuleDefinition(mod);
      final scDef = SystemCSynthModuleDefinition(mod);

      _expectConsistentNames(
        _collectNames(svDef),
        _collectNames(scDef),
        context: '_FlopModule',
      );
    });

    test('combinational module - names match', () async {
      final mod = _CombModule(Logic(width: 8), Logic(width: 8));
      await mod.build();

      final svDef = SystemVerilogSynthModuleDefinition(mod);
      final scDef = SystemCSynthModuleDefinition(mod);

      _expectConsistentNames(
        _collectNames(svDef),
        _collectNames(scDef),
        context: '_CombModule',
      );
    });

    test('name collisions resolved identically', () async {
      final mod = _CollisionModule(Logic(width: 8));
      await mod.build();

      final svDef = SystemVerilogSynthModuleDefinition(mod);
      final scDef = SystemCSynthModuleDefinition(mod);

      _expectConsistentNames(
        _collectNames(svDef),
        _collectNames(scDef),
        context: '_CollisionModule',
      );
    });

    test('generateSystemC does not crash after generateSynth', () async {
      final mod = _FlopModule(Logic(), Logic(width: 8));
      await mod.build();

      // SV first, then SC — validates shared Namer state is safe.
      final sv = mod.generateSynth();
      expect(sv, contains('module'));

      final sc = mod.generateSystemC();
      expect(sc, contains('SC_MODULE'));
    });

    test('generateSynth does not crash after generateSystemC', () async {
      final mod = _FlopModule(Logic(), Logic(width: 8));
      await mod.build();

      // SC first, then SV — reverse order.
      final sc = mod.generateSystemC();
      expect(sc, contains('SC_MODULE'));

      final sv = mod.generateSynth();
      expect(sv, contains('module'));
    });

    test('signal names in generated output match between SV and SC', () async {
      final mod = _Outer(Logic(width: 8), Logic(width: 8));
      await mod.build();

      final sv = mod.generateSynth();
      final sc = mod.generateSystemC();

      // Port names must appear in both outputs.
      for (final portName in [...mod.inputs.keys, ...mod.outputs.keys]) {
        expect(sv, contains(portName),
            reason: 'SV output should contain port "$portName"');
        expect(sc, contains(portName),
            reason: 'SC output should contain port "$portName"');
      }
    });

    test('scLineMap is populated with port and signal positions', () async {
      final mod = _Outer(Logic(width: 8), Logic(width: 8));
      await mod.build();

      // Access the SystemCSynthesisResult to check scLineMap.
      final synthBuilder = SynthBuilder(mod, SystemCSynthesizer());
      final results = synthBuilder.synthesisResults;

      // The top-level module's result should have line map entries.
      final topResult = results.firstWhere((r) => r.module == mod);
      expect(topResult, isA<SystemCSynthesisResult>());
      final scResult = topResult as SystemCSynthesisResult

        // Force text generation (which populates the line map).
        ..toFileContents();

      final lineMap = scResult.scLineMap;

      // Port names should have entries.
      for (final portName in [...mod.inputs.keys, ...mod.outputs.keys]) {
        expect(lineMap, contains(portName),
            reason: 'scLineMap should contain port "$portName"');
        // Each entry should be a non-empty list of 'line:col' strings.
        final positions = lineMap[portName]!;
        expect(positions, isNotEmpty,
            reason: 'Entry for "$portName" should have at least one position');
        for (final p in positions) {
          expect(p, matches(RegExp(r'^\d+:\d+$')),
              reason: 'Position "$p" for "$portName" '
                  'should be "line:col" format');
        }
      }
    });

    test('scLineMap positions match actual text positions', () async {
      final mod = _CombModule(Logic(width: 8), Logic(width: 8));
      await mod.build();

      final synthBuilder = SynthBuilder(mod, SystemCSynthesizer());
      final results = synthBuilder.synthesisResults;
      final topResult =
          results.firstWhere((r) => r.module == mod) as SystemCSynthesisResult;
      final text = topResult.toFileContents();
      final lineMap = topResult.scLineMap;
      final lines = text.split('\n');

      // Verify that every recorded position actually contains the symbol name.
      for (final entry in lineMap.entries) {
        final name = entry.key;
        for (final lineCol in entry.value) {
          final parts = lineCol.split(':');
          final line = int.parse(parts[0]) - 1; // 0-based
          final col = int.parse(parts[1]) - 1; // 0-based

          expect(line, lessThan(lines.length),
              reason: 'Line for "$name" should be within text');
          expect(lines[line], contains(name),
              reason: 'Line ${line + 1} should contain "$name".\n'
                  'Actual line: "${lines[line]}"');
          // Verify column position points to the name.
          final colEnd = col + name.length;
          if (colEnd <= lines[line].length) {
            expect(lines[line].substring(col, colEnd), equals(name),
                reason: 'Column position for "$name" should point to the name');
          }
        }
      }
    });

    test('scLineMap records multiple positions for re-assigned signals',
        () async {
      // _CombModule drives output `y` from two arms of an If/Else, so the
      // SystemC output contains the declaration line plus two assignment
      // LHS lines for `y`. All three should be recorded.
      final mod = _CombModule(Logic(width: 8), Logic(width: 8));
      await mod.build();

      final synthBuilder = SynthBuilder(mod, SystemCSynthesizer());
      final results = synthBuilder.synthesisResults;
      final topResult =
          results.firstWhere((r) => r.module == mod) as SystemCSynthesisResult;
      final text = topResult.toFileContents();
      final lineMap = topResult.scLineMap;
      final lines = text.split('\n');

      final yPositions = lineMap['y'];
      expect(yPositions, isNotNull, reason: 'output `y` must be recorded');
      expect(yPositions!.length, greaterThanOrEqualTo(3),
          reason: 'Expected the declaration plus at least two assignment '
              'positions for `y`, got: $yPositions');

      // Positions must be in textual (line-number) order.
      final lineNumbers =
          yPositions.map((p) => int.parse(p.split(':')[0])).toList();
      final sorted = [...lineNumbers]..sort();
      expect(lineNumbers, equals(sorted),
          reason: 'scLineMap positions must be in source order');

      // No duplicates.
      expect(yPositions.toSet().length, equals(yPositions.length),
          reason: 'scLineMap should not record duplicate positions');

      // Each recorded line must literally contain `y` at the recorded col.
      for (final p in yPositions) {
        final parts = p.split(':');
        final line = int.parse(parts[0]) - 1;
        final col = int.parse(parts[1]) - 1;
        expect(lines[line].substring(col, col + 1), equals('y'),
            reason: 'Position $p should point to `y`');
      }

      // Verify at least two of the recorded lines are assignment LHS
      // (i.e. line text matches `<spaces>y<spaces>=<non `=`>`).
      final assignLhsRe = RegExp(r'^\s*y\s*=(?!=)');
      final assignmentLines = yPositions.where((p) {
        final line = int.parse(p.split(':')[0]) - 1;
        return assignLhsRe.hasMatch(lines[line]);
      }).toList();
      expect(assignmentLines.length, greaterThanOrEqualTo(2),
          reason: 'Expected at least two assignment LHS lines for `y`, '
              'got: $assignmentLines');
    });
  });
}
