// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// naming_consistency_test.dart
// Validates that both the SystemVerilog synthesizer and a base
// SynthModuleDefinition (used by the netlist synthesizer) produce
// consistent signal names via the shared Module.namer.
//
// 2026 April 10
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/systemverilog/systemverilog_synth_module_definition.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';
import 'package:test/test.dart';

// ── Helper modules ──────────────────────────────────────────────────

/// A simple module with ports, internal wires, and a sub-module.
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

/// A module with a constant assignment (exercises const naming).
class _ConstModule extends Module {
  _ConstModule(Logic a) : super(name: 'constmod') {
    a = addInput('a', a, width: 8);
    final c = Const(0x42, width: 8).named('myConst', naming: Naming.mergeable);
    addOutput('y', width: 8) <= a + c;
  }
}

/// A module with Naming.renameable and Naming.mergeable signals.
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

/// A module with a FlipFlop sub-module.
class _FlopOuter extends Module {
  _FlopOuter(Logic clk, Logic d) : super(name: 'flopouter') {
    clk = addInput('clk', clk);
    d = addInput('d', d, width: 8);
    addOutput('q', width: 8) <= flop(clk, d);
  }
}

class _CollapsedInstanceCollidingNames extends Module {
  late final Logic retainedDup;

  _CollapsedInstanceCollidingNames(Logic a, Logic b)
      : super(name: 'collapsedInstanceCollidingNames') {
    a = addInput('a', a);
    b = addInput('b', b);
    final y = addOutput('y');
    final z = addOutput('z');

    final collapsedInstanceOut = And2Gate(a, b, name: 'dup').out;
    retainedDup = Logic(name: 'dup');

    retainedDup <= a | b;
    y <= collapsedInstanceOut ^ retainedDup;
    z <= retainedDup;
  }
}

Future<String> _retainedDupNameAfter(
  SynthModuleDefinition Function(_CollapsedInstanceCollidingNames)
      createDefinition,
) async {
  final mod = _CollapsedInstanceCollidingNames(Logic(), Logic());
  await mod.build();

  createDefinition(mod);

  return mod.namer.signalNameOfBest([mod.retainedDup]);
}

/// Builds [SynthModuleDefinition]s from both bases and collects a
/// Logic→name mapping for all present SynthLogics.
///
/// Returns maps from Logic to its resolved signal name.
Map<Logic, String> _collectNames(SynthModuleDefinition def) {
  final names = <Logic, String>{};
  for (final sl in [
    ...def.inputs,
    ...def.outputs,
    ...def.inOuts,
    ...def.internalSignals,
  ]) {
    // Skip SynthLogics whose name was never picked (replaced/pruned).
    try {
      final n = sl.name;
      for (final logic in sl.logics) {
        names[logic] = n;
      }
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      // name not picked — skip
    }
  }
  return names;
}

void main() {
  group('naming consistency', () {
    test('SV and base SynthModuleDefinition agree on port names', () async {
      final mod = _Outer(Logic(width: 8), Logic(width: 8));
      await mod.build();

      // SV synthesizer path
      final svDef = SystemVerilogSynthModuleDefinition(mod);

      // Base path (same as netlist synthesizer uses)
      // Since namer is late final, the second constructor reuses
      // the same naming state — names must be consistent.
      final baseDef = SynthModuleDefinition(mod);

      final svNames = _collectNames(svDef);
      final baseNames = _collectNames(baseDef);

      // Every Logic present in both must have the same name.
      for (final logic in svNames.keys) {
        if (baseNames.containsKey(logic)) {
          expect(
            baseNames[logic],
            svNames[logic],
            reason: 'Name mismatch for ${logic.name} '
                '(${logic.runtimeType}, naming=${logic.naming})',
          );
        }
      }

      // Port names specifically must match.
      for (final port in [...mod.inputs.values, ...mod.outputs.values]) {
        expect(
          svNames[port],
          isNotNull,
          reason: 'SV def should have port ${port.name}',
        );
        expect(
          baseNames[port],
          isNotNull,
          reason: 'Base def should have port ${port.name}',
        );
        expect(
          svNames[port],
          baseNames[port],
          reason: 'Port name must match for ${port.name}',
        );
      }
    });

    test('constant naming is consistent', () async {
      final mod = _ConstModule(Logic(width: 8));
      await mod.build();

      final svDef = SystemVerilogSynthModuleDefinition(mod);
      final baseDef = SynthModuleDefinition(mod);

      final svNames = _collectNames(svDef);
      final baseNames = _collectNames(baseDef);

      for (final logic in svNames.keys) {
        if (baseNames.containsKey(logic)) {
          expect(
            baseNames[logic],
            svNames[logic],
            reason: 'Name mismatch for ${logic.name}',
          );
        }
      }
    });

    test('mixed naming (renameable + mergeable) is consistent', () async {
      final mod = _MixedNaming(Logic(width: 8));
      await mod.build();

      final svDef = SystemVerilogSynthModuleDefinition(mod);
      final baseDef = SynthModuleDefinition(mod);

      final svNames = _collectNames(svDef);
      final baseNames = _collectNames(baseDef);

      for (final logic in svNames.keys) {
        if (baseNames.containsKey(logic)) {
          expect(
            baseNames[logic],
            svNames[logic],
            reason: 'Name mismatch for ${logic.name}',
          );
        }
      }
    });

    test('flop module naming is consistent', () async {
      final mod = _FlopOuter(Logic(), Logic(width: 8));
      await mod.build();

      final svDef = SystemVerilogSynthModuleDefinition(mod);
      final baseDef = SynthModuleDefinition(mod);

      final svNames = _collectNames(svDef);
      final baseNames = _collectNames(baseDef);

      for (final logic in svNames.keys) {
        if (baseNames.containsKey(logic)) {
          expect(
            baseNames[logic],
            svNames[logic],
            reason: 'Name mismatch for ${logic.name}',
          );
        }
      }
    });

    test('namer is shared across multiple SynthModuleDefinitions', () async {
      final mod = _Outer(Logic(width: 8), Logic(width: 8));
      await mod.build();

      // Build one def, then build another — same namer instance.
      final def1 = SynthModuleDefinition(mod);
      final def2 = SynthModuleDefinition(mod);

      final names1 = _collectNames(def1);
      final names2 = _collectNames(def2);

      for (final logic in names1.keys) {
        if (names2.containsKey(logic)) {
          expect(
            names2[logic],
            names1[logic],
            reason: 'Shared namer should produce same name for '
                '${logic.name}',
          );
        }
      }
    });

    test('Namer.signalNameOfBest matches SynthLogic.name for ports', () async {
      final mod = _Outer(Logic(width: 8), Logic(width: 8));
      await mod.build();

      final def = SynthModuleDefinition(mod);
      final synthNames = _collectNames(def);

      // Module.namer.signalNameOfBest uses Namer directly
      for (final port in [...mod.inputs.values, ...mod.outputs.values]) {
        final moduleName = mod.namer.signalNameOfBest([port]);
        final synthName = synthNames[port];
        expect(
          synthName,
          moduleName,
          reason:
              'SynthLogic.name and Module.namer.signalNameOfBest must agree '
              'for port ${port.name}',
        );
      }
    });

    test(
      'submodule instance names are allocated from the shared namespace',
      () async {
        // Instance names come from Module.namer.instanceNameOf,
        // which shares the same namespace as signal names.
        final mod = _Outer(Logic(width: 8), Logic(width: 8));
        await mod.build();

        final def = SynthModuleDefinition(mod);

        final instNames = def.subModuleInstantiations
            .where((s) => s.needsInstantiation)
            .map((s) => s.name)
            .toSet();

        // The inner module instance should have a name
        expect(
          instNames,
          isNotEmpty,
          reason: 'Should have at least one submodule instance',
        );

        // Instance names are claimed in the shared namespace.
        for (final name in instNames) {
          expect(
            mod.namer.isAvailable(name),
            isFalse,
            reason: 'Instance name "$name" should be claimed in the '
                'namespace',
          );
        }
      },
    );

    test(
      'submodule instance names are stable across repeated definitions',
      () async {
        final mod = _Outer(Logic(width: 8), Logic(width: 8));
        await mod.build();

        final def1 = SynthModuleDefinition(mod);
        final def2 = SynthModuleDefinition(mod);

        final names1 = def1.subModuleInstantiations
            .where((s) => s.needsInstantiation)
            .map((s) => s.name)
            .toList();
        final names2 = def2.subModuleInstantiations
            .where((s) => s.needsInstantiation)
            .map((s) => s.name)
            .toList();

        expect(
          names2,
          names1,
          reason: 'Repeated synthesis passes should reuse cached instance '
              'names instead of drifting numeric suffixes.',
        );
      },
    );

    test(
      'collapsed instance does not steal basename from retained signal',
      () async {
        final baseName = await _retainedDupNameAfter(SynthModuleDefinition.new);
        await Simulator.reset();

        final svName = await _retainedDupNameAfter(
          SystemVerilogSynthModuleDefinition.new,
        );

        expect(svName, equals(baseName));
        expect(baseName, equals('dup'));
      },
    );

    test(
      'struct-slice submodule names are stable across repeated definitions',
      () async {
        // Regression test for _BusSubsetForStructSlice.instanceNameKey:
        // Each SynthModuleDefinition pass creates fresh _BusSubsetForStructSlice
        // instances for any submodule with a LogicStructure output port.
        // Without the _destination override the namer cache misses on those
        // fresh instances and allocates new suffixes every pass, so the same
        // struct field would be named "struct_slice" on pass 1 and
        // "struct_slice_0" on pass 2.
        final mod = _StructSliceParentMod();
        await mod.build();

        final def1 = SynthModuleDefinition(mod);
        final def2 = SynthModuleDefinition(mod);

        // Only consider instantiations that are emitted (struct_slice and the
        // child module itself both have needsInstantiation=true here).
        final sliceNames1 = def1.subModuleInstantiations
            .where((s) => s.needsInstantiation)
            .map((s) => s.name)
            .where((n) => n.startsWith('struct_slice'))
            .toList()
          ..sort();
        final sliceNames2 = def2.subModuleInstantiations
            .where((s) => s.needsInstantiation)
            .map((s) => s.name)
            .where((n) => n.startsWith('struct_slice'))
            .toList()
          ..sort();

        expect(
          sliceNames1,
          isNotEmpty,
          reason: 'Expected at least one struct_slice instance to be '
              'created for the _TwoFieldStruct output port.',
        );
        expect(
          sliceNames2,
          sliceNames1,
          reason: 'struct_slice instance names must not drift across repeated '
              'synthesis passes — requires _BusSubsetForStructSlice to override '
              'instanceNameKey with the stable destination Logic.',
        );
      },
    );
  });
}

// ─── Fixtures ─────────────────────────────────────────────────────────────────

class _TwoFieldStruct extends LogicStructure {
  final Logic a;
  final Logic b;

  factory _TwoFieldStruct({String name = 'st'}) =>
      _TwoFieldStruct._(Logic(name: 'a', width: 4), Logic(name: 'b', width: 4),
          name: name);

  _TwoFieldStruct._(this.a, this.b, {required super.name})
      : super([a, b]);

  @override
  LogicStructure clone({String? name}) =>
      _TwoFieldStruct(name: name ?? this.name);
}

/// A module with a [LogicStructure] output port.
///
/// When this module is instantiated inside a parent, synthesis of the parent
/// calls [_subsetReceiveStructPort] for this module's struct output, creating
/// one [_BusSubsetForStructSlice] per leaf element.
class _StructOutputMod extends Module {
  late final _TwoFieldStruct out;

  _StructOutputMod() : super(name: '_StructOutputMod') {
    out = addTypedOutput('out', _TwoFieldStruct.new)
      ..a.gets(Const(0, width: 4))
      ..b.gets(Const(0, width: 4));
  }
}

/// Parent module whose synthesis pass creates [_BusSubsetForStructSlice]
/// instances for [_StructOutputMod]'s struct output port.
class _StructSliceParentMod extends Module {
  _StructSliceParentMod() : super(name: '_StructSliceParentMod') {
    final sub = _StructOutputMod();
    // Consume one leaf so the parent has a meaningful output.
    addOutput('flat', width: 4) <= sub.out.a;
  }
}
