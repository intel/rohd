// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// instance_signal_name_collision_test.dart
// Tests that submodule instance names and signal names share a single
// namespace, so a collision between them results in uniquification.
//
// 2026 April 18
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';
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
/// Because both identifiers live in a single shared namespace, one of them
/// will be suffixed to avoid collision.
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
  group('instance / signal name collision (shared namespace)', () {
    late _CollidingParent mod;
    late SynthModuleDefinition def;

    setUpAll(() async {
      mod = _CollidingParent(Logic(width: 8));
      await mod.build();
      def = SynthModuleDefinition(mod);
    });

    test('internal signal named "inner" retains its exact name', () {
      // The reserved signal should keep its exact name.
      final sl = def.internalSignals.cast<SynthLogic?>().firstWhere(
            (s) => s!.logics.any((l) => l.name == 'inner'),
            orElse: () => null,
          );
      expect(sl, isNotNull, reason: 'Expected to find SynthLogic for "inner"');
      expect(sl!.name, 'inner',
          reason: 'Reserved signal "inner" must keep its exact name');
    });

    test(
        'submodule instance is uniquified because signal '
        '"inner" already claimed the name', () {
      final inst = def.subModuleInstantiations
          .where((s) => s.needsInstantiation)
          .cast<SynthSubModuleInstantiation?>()
          .firstWhere(
            (s) => s!.module.name == 'inner',
            orElse: () => null,
          );
      expect(inst, isNotNull, reason: 'Expected submodule instance for inner');
      // The instance should be suffixed since the signal took "inner" first.
      expect(inst!.name, isNot('inner'),
          reason: 'Instance should be uniquified when signal already '
              'claims "inner"');
    });
  });
}
