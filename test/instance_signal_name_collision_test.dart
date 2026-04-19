// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// instance_signal_name_collision_test.dart
// Regression test that demonstrates the bug present in the main branch where
// submodule instance names and signal names share a single Uniquifier.
//
// In SystemVerilog, signal identifiers and instance identifiers live in
// *separate* namespaces, so it is perfectly legal to have a signal called
// "inner" and a module instance also called "inner" in the same scope.
//
// When a single shared Uniquifier is used (main-branch behaviour), the second
// name to be allocated gets spuriously suffixed (e.g. "inner_0"), which
// produces incorrect generated SV.
//
// 2026 April 18
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';
import 'package:rohd/src/utilities/namer.dart';
import 'package:test/test.dart';

// ── Minimal repro modules ────────────────────────────────────────────────────

/// Leaf module whose default instance name is "inner".
class _Inner extends Module {
  _Inner(Logic a) : super(name: 'inner') {
    a = addInput('a', a, width: a.width);
    addOutput('y', width: a.width) <= a;
  }
}

/// Parent module that:
///   • instantiates [_Inner] (default instance name: "inner")
///   • names an internal wire "inner" as well
///
/// In SV the two identifiers live in different namespaces, so both should
/// be emitted as "inner" without any suffix.
class _CollidingParent extends Module {
  _CollidingParent(Logic a) : super(name: 'colliding_parent') {
    a = addInput('a', a, width: a.width);

    // Internal wire explicitly named "inner".
    final inner = Logic(name: 'inner', width: a.width, naming: Naming.reserved)
      ..gets(a);

    // Submodule whose uniqueInstanceName will also be "inner".
    final sub = _Inner(inner);

    addOutput('y', width: a.width) <= sub.output('y');
  }
}

// ── Test ─────────────────────────────────────────────────────────────────────

void main() {
  group('instance / signal name collision (main-branch bug)', () {
    late _CollidingParent mod;
    late SynthModuleDefinition def;
    late bool previousSetting;

    setUpAll(() async {
      previousSetting = Namer.uniquifySignalAndInstanceNames;
      Namer.uniquifySignalAndInstanceNames = false;

      mod = _CollidingParent(Logic(width: 8));
      await mod.build();
      def = SynthModuleDefinition(mod);
    });

    tearDownAll(() {
      Namer.uniquifySignalAndInstanceNames = previousSetting;
    });

    test('internal signal named "inner" retains its exact name', () {
      // Find the SynthLogic for the reserved "inner" wire.
      final sl = def.internalSignals.cast<SynthLogic?>().firstWhere(
            (s) => s!.logics.any((l) => l.name == 'inner'),
            orElse: () => null,
          );
      expect(sl, isNotNull, reason: 'Expected to find SynthLogic for "inner"');
      expect(sl!.name, 'inner',
          reason: 'Signal "inner" must not be suffixed to "inner_0"');
    });

    test('submodule instance named "inner" retains its exact name', () {
      final inst = def.subModuleInstantiations
          .where((s) => s.needsInstantiation)
          .cast<SynthSubModuleInstantiation?>()
          .firstWhere(
            (s) => s!.module.name == 'inner',
            orElse: () => null,
          );
      expect(inst, isNotNull, reason: 'Expected submodule instance for inner');
      expect(inst!.name, 'inner',
          reason: 'Instance "inner" must not be suffixed to "inner_0"');
    });

    test('signal and instance may share the name "inner" without collision',
        () {
      // Both should be "inner", not one of them "inner_0".
      final sl = def.internalSignals.cast<SynthLogic?>().firstWhere(
            (s) => s!.logics.any((l) => l.name == 'inner'),
            orElse: () => null,
          );
      final inst = def.subModuleInstantiations
          .where((s) => s.needsInstantiation)
          .cast<SynthSubModuleInstantiation?>()
          .firstWhere(
            (s) => s!.module.name == 'inner',
            orElse: () => null,
          );
      expect(sl?.name, 'inner');
      expect(inst?.name, 'inner');
    });
  });
}
