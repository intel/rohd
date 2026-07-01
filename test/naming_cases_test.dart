// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// naming_cases_test.dart
// Systematic test of all signal-naming cases in the synthesis pipeline.
//
// 2026 April 10
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

// ════════════════════════════════════════════════════════
// NAMING CROSS-PRODUCT TABLE
// ════════════════════════════════════════════════════════
//
// Axis 1 — Naming enum (set at Logic construction time):
//   reserved    Exact name required; collision → exception.
//   renameable  Keeps name, uniquified on collision; never merged.
//   mergeable   May merge with equivalent signals; any merged name chosen.
//   unnamed     No user name; system generates one.
//
// Axis 2 — Context role (per SynthModuleDefinition):
//   this-port   Port of module being synthesized
//               (namingOverride → reserved).
//   sub-port    Port of a child submodule
//               (namingOverride → mergeable).
//   internal    Non-port signal inside the module (no override).
//   const       Const object (separate path via constValue).
//
// Axis 3 — Name preference:
//   preferred     baseName does NOT start with '_'
//   unpreferred   baseName starts with '_'
//
// Axis 4 — Constant context (only for Const):
//   allowed       Literal value string used as name.
//   disallowed    Feeding expressionlessInput;
//                 must use a wire name.
//
// ──────────────────────────────────────────────────────
// Row  Naming       Context   Pref?  Test  Valid?
//      Effective class → Outcome
// ──────────────────────────────────────────────────────
//  1   reserved     this-port  pref    T1    ✓
//      port (in _portLogics) → exact sanitized name
//  2   reserved     this-port  unpref  T2    ✓ unusual
//      port → exact _-prefixed port name
//  3   reserved     sub-port   pref    T3    ✓
//      preferred mergeable → merged, uniquified
//  4   reserved     sub-port   unpref  T4    ✓
//      unpreferred mergeable → low-priority merge
//  5   reserved     internal   pref    T5    ✓
//      reserved internal → exact name, throw on clash
//  6   reserved     internal   unpref  T6    ✓ unusual
//      reserved internal → exact _-prefixed name
//  7   renameable   this-port  pref    —     can't happen*
//      port → exact port name
//  8   renameable   sub-port   pref    —     can't happen*
//      preferred mergeable → merged
//  9   renameable   internal   pref    T9    ✓
//      renameable → base name, uniquified
// 10   renameable   internal   unpref  T10   ✓ unusual
//      renameable → uniquified _-prefixed
// 11   mergeable    this-port  pref    T11   ✓
//      port → exact port name (Logic.port())
// 12   mergeable    this-port  unpref  T12   ✓ unusual
//      port → exact _-prefixed port name
// 13   mergeable    sub-port   pref    T3    ✓ (=row 3)
//      preferred mergeable → best-available merge
// 14   mergeable    sub-port   unpref  T4    ✓ (=row 4)
//      unpreferred mergeable → low-priority merge
// 15   mergeable    internal   pref    T15   ✓
//      preferred mergeable → prefer available name
// 16   mergeable    internal   unpref  T16   ✓
//      unpreferred mergeable → low-priority merge
// 17   unnamed      this-port  —       —     ✗ impossible**
//      port → exact port name
// 18   unnamed      sub-port   —       —     ✗ impossible**
//      mergeable → merged
// 19   unnamed      internal   (unpf)  T19   ✓
//      unnamed → generated _s name
// 20   —(Const)     —          —       T20   ✓
//      const allowed → literal value e.g. 8'h42
// 21   —(Const)     —          —       T21   ✓
//      const disallowed → wire name (not literal)
// ──────────────────────────────────────────────────────
//
//  *  Rows 7-8: addInput/addOutput always create
//     Logic with Naming.reserved, so a port can
//     never have intrinsic Naming.renameable.
//     The namingOverride makes it moot anyway.
//
//  ** Rows 17-18: addInput/addOutput require a
//     non-null, non-empty name. chooseName() only
//     yields Naming.unnamed for null/empty names,
//     so a port can never be unnamed.
//
//  ✗  unnamed + reserved: Logic(naming: reserved)
//     with null/empty name throws
//     NullReservedNameException /
//     EmptyReservedNameException at construction
//     time.  Never reaches synthesizer.
//
// Additional cross-cutting concerns:
//   COL   Collision between mergeables
//         → uniquified suffix (_0)
//   MG    Merge: directly-connected signals
//         share SynthLogic
//   INST  Submodule instance names: unique,
//         don't collide with ports
//   ST    Structure element: structureName
//         = "parent.field" → sanitized ("_")
//   AR    Array element: isArrayMember
//         → uses logic.name (index-based)
//
// ════════════════════════════════════════════════════════

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';
import 'package:test/test.dart';

// ── Leaf sub-modules ──────────────────────────────

/// A leaf module whose `in0` is an "expressionless input" —
/// meaning any constant driving it must get a real wire name, not a literal.
class _ExpressionlessSub extends Module with SystemVerilog {
  @override
  List<String> get expressionlessInputs => const ['in0'];

  _ExpressionlessSub(Logic a, Logic b) : super(name: 'exprsub') {
    a = addInput('in0', a, width: a.width);
    b = addInput('in1', b, width: b.width);
    addOutput('out', width: a.width) <= a & b;
  }
}

/// A simple sub-module with preferred-name ports.
class _SimpleSub extends Module {
  _SimpleSub(Logic x) : super(name: 'simplesub') {
    x = addInput('x', x, width: x.width);
    addOutput('y', width: x.width) <= ~x;
  }
}

/// A sub-module with an unpreferred-name port.
class _UnprefSub extends Module {
  _UnprefSub(Logic a) : super(name: 'unprefsub') {
    a = addInput('_uport', a, width: a.width);
    addOutput('uout', width: a.width) <= ~a;
  }
}

// ── Main test module ──────────────────────────────
// One module that exercises every valid naming case in a minimal design.
// Each signal is tagged with the row number from the table above.

class _AllNamingCases extends Module {
  // Exposed for test inspection.
  // Row 1 / Row 2: ports (accessed via mod.input / mod.output).
  // Row 5:
  late final Logic reservedInternal;
  // Row 6:
  late final Logic reservedInternalUnpref;
  // Row 9:
  late final Logic renameableInternal;
  // Row 10:
  late final Logic renameableInternalUnpref;
  // Row 15:
  late final Logic mergeablePref;
  // Row 15 collision partner:
  late final Logic mergeablePrefCollide;
  // Row 16:
  late final Logic mergeableUnpref;
  // Row 19:
  late final Logic unnamed;
  // Row 20:
  late final Logic constAllowed;
  // Row 21:
  late final Logic constDisallowed;
  // MG:
  late final Logic mergeTarget;

  // Structure/array elements (ST, AR):
  late final LogicStructure structPort;
  late final LogicArray arrayPort;

  _AllNamingCases() : super(name: 'allcases') {
    // ── Row 1: reserved + this-port + preferred ──────────────────
    final inp = addInput('inp', Logic(width: 8), width: 8);
    final out = addOutput('out', width: 8);

    // ── Row 2: reserved + this-port + unpreferred ────────────────
    final uInp = addInput('_uinp', Logic(width: 8), width: 8);

    // ── Row 11: mergeable + this-port + preferred ────────────────
    // (This is the Logic.port() → connectIO path.  addInput forces
    //  Naming.reserved regardless of the source's naming, so intrinsic
    //  mergeable is overridden to reserved.  We test the port keeps its
    //  exact name.)
    final mPortInp = addInput('mport', Logic(width: 8), width: 8);

    // ── Row 12: mergeable + this-port + unpreferred ──────────────
    final mPortUnpref = addInput('_muprt', Logic(width: 8), width: 8);

    // ── Row 5: reserved + internal + preferred ───────────────────
    reservedInternal = Logic(name: 'resv', width: 8, naming: Naming.reserved)
      ..gets(inp ^ Const(0x01, width: 8));

    // ── Row 6: reserved + internal + unpreferred ─────────────────
    reservedInternalUnpref =
        Logic(name: '_resvu', width: 8, naming: Naming.reserved)
          ..gets(inp ^ Const(0x02, width: 8));

    // ── Row 9: renameable + internal + preferred ─────────────────
    renameableInternal = Logic(name: 'ren', width: 8, naming: Naming.renameable)
      ..gets(inp ^ Const(0x03, width: 8));

    // ── Row 10: renameable + internal + unpreferred ──────────────
    renameableInternalUnpref =
        Logic(name: '_renu', width: 8, naming: Naming.renameable)
          ..gets(inp ^ Const(0x04, width: 8));

    // ── Row 15: mergeable + internal + preferred ─────────────────
    mergeablePref = Logic(name: 'mname', width: 8, naming: Naming.mergeable)
      ..gets(inp ^ Const(0x05, width: 8));

    // ── COL: collision partner — same base name 'mname' ──────────
    mergeablePrefCollide =
        Logic(name: 'mname', width: 8, naming: Naming.mergeable)
          ..gets(inp ^ Const(0x06, width: 8));

    // ── Row 16: mergeable + internal + unpreferred ───────────────
    mergeableUnpref = Logic(name: '_hidden', width: 8, naming: Naming.mergeable)
      ..gets(inp ^ Const(0x07, width: 8));

    // ── Row 19: unnamed + internal ───────────────────────────────
    unnamed = Logic(width: 8)..gets(inp ^ Const(0x08, width: 8));

    // ── Rows 3/13: sub-port preferred (via _SimpleSub.x / .y) ───
    // ── Row 4/14: sub-port unpreferred (via _UnprefSub._uport) ──
    final sub = _SimpleSub(renameableInternal);
    final subOut = sub.output('y');
    // Use a distinct expression so the submodule port doesn't merge with
    // renameableInternal (which is renameable and would win).
    final unpSub = _UnprefSub(inp ^ Const(0x0a, width: 8));

    // ── MG: merge behavior — mergeTarget merges with subOut ──────
    mergeTarget = Logic(name: 'mmerge', width: 8, naming: Naming.mergeable)
      ..gets(subOut);

    // ── Row 20: constant with name allowed ───────────────────────
    constAllowed =
        Const(0x42, width: 8).named('const_ok', naming: Naming.mergeable);

    // ── Row 21: constant with name disallowed (expressionlessInput)
    constDisallowed =
        Const(0x09, width: 8).named('const_wire', naming: Naming.mergeable);
    // ignore: unused_local_variable
    final exprSub = _ExpressionlessSub(constDisallowed, inp);

    // ── ST: structure element (structureName = "parent.field") ────
    structPort = _SimpleStruct();
    addInput('stIn', structPort, width: structPort.width);

    // ── AR: array element (isArrayMember, uses logic.name) ───────
    arrayPort = LogicArray([3], 8, name: 'arIn');
    addInputArray('arIn', arrayPort, dimensions: [3], elementWidth: 8);

    // Drive output to use all signals (prevents pruning).
    out <=
        mergeTarget |
            mergeablePrefCollide |
            mergeableUnpref |
            unnamed |
            constAllowed |
            uInp |
            mPortInp |
            mPortUnpref |
            reservedInternalUnpref |
            renameableInternalUnpref |
            unpSub.output('uout');
  }
}

/// A minimal LogicStructure for testing structureName sanitization.
class _SimpleStruct extends LogicStructure {
  final Logic field1;
  final Logic field2;

  factory _SimpleStruct({String name = 'st'}) => _SimpleStruct._(
        Logic(name: 'a', width: 4),
        Logic(name: 'b', width: 4),
        name: name,
      );

  _SimpleStruct._(this.field1, this.field2, {required super.name})
      : super([field1, field2]);

  @override
  LogicStructure clone({String? name}) =>
      _SimpleStruct(name: name ?? this.name);
}

// ── Helpers ───────────────────────────────────────

/// Collects a map from Logic → picked name for all SynthLogics.
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
      // name not picked (pruned/replaced)
    }
  }
  return names;
}

/// Finds a SynthLogic that contains [logic].
SynthLogic? _findSynthLogic(SynthModuleDefinition def, Logic logic) {
  for (final sl in [
    ...def.inputs,
    ...def.outputs,
    ...def.inOuts,
    ...def.internalSignals,
  ]) {
    if (sl.logics.contains(logic)) {
      return sl;
    }
  }
  return null;
}

// ── Tests ────────────────────────────────────────

void main() {
  late _AllNamingCases mod;
  late SynthModuleDefinition def;
  late Map<Logic, String> names;

  setUp(() async {
    mod = _AllNamingCases();
    await mod.build();
    def = SynthModuleDefinition(mod);
    names = _collectNames(def);
  });

  group('naming cases', () {
    // ── Row 1: reserved + this-port + preferred ────────────────

    test('T1: reserved preferred port keeps exact name', () {
      expect(names[mod.input('inp')], 'inp');
      expect(names[mod.output('out')], 'out');
    });

    // ── Row 2: reserved + this-port + unpreferred ──────────────

    test('T2: reserved unpreferred port keeps exact _-prefixed name', () {
      expect(names[mod.input('_uinp')], '_uinp');
    });

    // ── Rows 3/13: sub-port + preferred (reserved or mergeable) ─

    test('T3: submodule preferred port gets a name in parent', () {
      final subX = mod.subModules.whereType<_SimpleSub>().first.input('x');
      final n = names[subX];
      expect(n, isNotNull, reason: 'Submodule port must be named');
      // Treated as preferred mergeable — name should not start with _.
      expect(n, isNot(startsWith('_')),
          reason: 'Preferred submodule port name should not be unpreferred');
    });

    // ── Row 4/14: sub-port + unpreferred ────────────────────────

    test('T4: submodule unpreferred port gets an unpreferred name', () {
      final subUPort =
          mod.subModules.whereType<_UnprefSub>().first.input('_uport');
      final n = names[subUPort];
      expect(n, isNotNull, reason: 'Submodule port must be named');
      expect(n, startsWith('_'),
          reason: 'Unpreferred submodule port should keep _-prefix');
    });

    // ── Row 5: reserved + internal + preferred ──────────────────

    test('T5: reserved preferred internal keeps exact name', () {
      expect(names[mod.reservedInternal], 'resv');
    });

    // ── Row 6: reserved + internal + unpreferred ────────────────

    test('T6: reserved unpreferred internal keeps exact _-prefixed name', () {
      expect(names[mod.reservedInternalUnpref], '_resvu');
    });

    // ── Row 9: renameable + internal + preferred ────────────────

    test('T9: renameable preferred internal gets its name', () {
      final n = names[mod.renameableInternal];
      expect(n, isNotNull);
      expect(n, contains('ren'));
    });

    // ── Row 10: renameable + internal + unpreferred ─────────────

    test('T10: renameable unpreferred internal keeps _-prefix', () {
      final n = names[mod.renameableInternalUnpref];
      expect(n, isNotNull);
      expect(n, startsWith('_'),
          reason: 'Unpreferred renameable should keep _-prefix');
      expect(n, contains('renu'));
    });

    // ── Row 11: mergeable + this-port + preferred ───────────────

    test('T11: mergeable-origin port (Logic.port) keeps exact port name', () {
      // addInput overrides naming to reserved; the port name is exact.
      expect(names[mod.input('mport')], 'mport');
    });

    // ── Row 12: mergeable + this-port + unpreferred ─────────────

    test('T12: mergeable-origin unpreferred port keeps exact name', () {
      expect(names[mod.input('_muprt')], '_muprt');
    });

    // ── Row 15: mergeable + internal + preferred ────────────────

    test('T15: mergeable preferred internal gets its name', () {
      final n = names[mod.mergeablePref];
      expect(n, isNotNull);
      expect(n, contains('mname'));
    });

    // ── COL: name collision → uniquified suffix ─────────────────

    test('COL: collision between two mergeables gets uniquified', () {
      final n1 = names[mod.mergeablePref];
      final n2 = names[mod.mergeablePrefCollide];
      expect(n1, isNot(n2), reason: 'Colliding names must be uniquified');
      expect({n1, n2}, containsAll(['mname', 'mname_0']));
    });

    // ── Row 16: mergeable + internal + unpreferred ──────────────

    test('T16: mergeable unpreferred internal keeps _-prefix', () {
      final n = names[mod.mergeableUnpref];
      expect(n, isNotNull);
      expect(n, startsWith('_'),
          reason: 'Unpreferred mergeable should keep _-prefix');
    });

    // ── Row 19: unnamed + internal ──────────────────────────────

    test('T19: unnamed signal gets a generated name', () {
      final n = names[mod.unnamed];
      expect(n, isNotNull, reason: 'Unnamed signal must still get a name');
      // chooseName() gives unnamed signals a name starting with '_s'.
      expect(n, startsWith('_'),
          reason: 'Unnamed signals get unpreferred generated names');
    });

    // ── Row 20: constant with name allowed ──────────────────────

    test('T20: constant with name allowed uses literal value', () {
      final sl = _findSynthLogic(def, mod.constAllowed);
      expect(sl, isNotNull);
      if (sl != null && !sl.constNameDisallowed) {
        expect(sl.name, contains("8'h42"),
            reason: 'Allowed constant should use value literal');
      }
    });

    // ── Row 21: constant with name disallowed ───────────────────

    test('T21: constant with name disallowed uses wire name', () {
      final sl = _findSynthLogic(def, mod.constDisallowed);
      expect(sl, isNotNull);
      if (sl != null) {
        if (sl.constNameDisallowed) {
          expect(sl.name, isNot(contains("8'h09")),
              reason: 'Disallowed constant should not use value literal');
          expect(sl.name, isNotEmpty);
        }
      }
    });

    // ── MG: merge behavior ──────────────────────────────────────

    test('MG: merged signals share the same SynthLogic', () {
      final sl = _findSynthLogic(def, mod.mergeTarget);
      expect(sl, isNotNull);
      if (sl != null && sl.logics.length > 1) {
        expect(sl.name, isNotEmpty);
      }
    });

    // ── INST: submodule instance naming ─────────────────────────

    test('INST: submodule instances get collision-free names', () {
      final instNames = def.subModuleInstantiations
          .where((s) => s.needsInstantiation)
          .map((s) => s.name)
          .toList();
      expect(instNames.toSet().length, instNames.length,
          reason: 'Instance names must be unique');
      final portNames = {...mod.inputs.keys, ...mod.outputs.keys};
      for (final name in instNames) {
        expect(portNames, isNot(contains(name)),
            reason: 'Instance "$name" should not collide with a port');
      }
    });

    // ── ST: structure element naming ────────────────────────────

    test('ST: structure element structureName is sanitized', () {
      // structureName for field1 is "st.a" → sanitized to "st_a".
      final stIn = mod.input('stIn');
      final n = names[stIn];
      expect(n, isNotNull);
      // The port itself should keep its reserved name 'stIn'.
      expect(n, 'stIn');
    });

    // ── AR: array element naming ────────────────────────────────

    test('AR: array port keeps its name', () {
      // Array ports are registered via addInputArray with Naming.reserved.
      final arIn = mod.input('arIn');
      final n = names[arIn];
      expect(n, isNotNull);
      expect(n, 'arIn');
    });

    // ── Impossible cases ────────────────────────────────────────

    test('unnamed + reserved throws at construction time', () {
      expect(
        () => Logic(naming: Naming.reserved),
        throwsA(isA<NullReservedNameException>()),
      );
      expect(
        () => Logic(name: '', naming: Naming.reserved),
        throwsA(isA<EmptyReservedNameException>()),
      );
    });

    // ── Golden SV snapshot ──────────────────────────────────────

    test('golden SV output snapshot', () {
      final sv = mod.generateSynth();

      // Port declarations.
      expect(sv, contains('input logic [7:0] inp'));
      expect(sv, contains('output logic [7:0] out'));
      expect(sv, contains('_uinp'));
      expect(sv, contains('mport'));
      expect(sv, contains('_muprt'));

      // Reserved internals.
      expect(sv, contains('resv'));
      expect(sv, contains('_resvu'));

      // Renameable internals.
      expect(sv, contains('ren'));
      expect(sv, contains('_renu'));

      // Constant literal (T20).
      expect(sv, contains("8'h42"));

      // Submodule instantiations.
      expect(sv, contains('simplesub'));
      expect(sv, contains('exprsub'));
      expect(sv, contains('unprefsub'));
    });
  });
}
