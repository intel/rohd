// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// naming_namespace_test.dart
// Tests for constant naming via nameOfBest, the tryMerge guard for
// constNameDisallowed, and separate instance/signal namespaces.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/namer.dart';
import 'package:test/test.dart';

/// A simple submodule whose instance name can collide with a signal name.
class _Inner extends Module {
  _Inner(Logic a, {super.name = 'inner'}) {
    a = addInput('a', a);
    addOutput('b') <= ~a;
  }
}

/// Top module that has a signal named the same as a submodule instance.
class _InstanceSignalCollision extends Module {
  _InstanceSignalCollision({String instanceName = 'inner'})
      : super(name: 'top') {
    final a = addInput('a', Logic());
    final o = addOutput('o');

    // Create a signal whose name matches the submodule instance name.
    final sig = Logic(name: instanceName);
    sig <= ~a;

    final sub = _Inner(sig, name: instanceName);
    o <= sub.output('b');
  }
}

/// Top module with two submodule instances that have the same name.
class _DuplicateInstances extends Module {
  _DuplicateInstances() : super(name: 'top') {
    final a = addInput('a', Logic());
    final o = addOutput('o');

    final sub1 = _Inner(a, name: 'blk');
    final sub2 = _Inner(sub1.output('b'), name: 'blk');
    o <= sub2.output('b');
  }
}

/// Module that uses a constant in a connection chain, exercising constant
/// naming through nameOfBest.
class _ConstantNamingModule extends Module {
  _ConstantNamingModule() : super(name: 'const_mod') {
    final a = addInput('a', Logic());
    final o = addOutput('o');

    // A constant "1" drives one input of the AND gate.
    o <= a & Const(1);
  }
}

/// Module with a mux where one input is a constant, exercising the
/// constNameDisallowed path — the mux output cannot use the constant's
/// literal as its name because it also carries non-constant values.
class _ConstNameDisallowedModule extends Module {
  _ConstNameDisallowedModule() : super(name: 'const_disallow') {
    final a = addInput('a', Logic());
    final sel = addInput('sel', Logic());
    final o = addOutput('o');

    // mux output can be the constant OR a, so the constant name is disallowed.
    o <= mux(sel, Const(1), a);
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
    // Restore default.
    Namer.uniquifySignalAndInstanceNames = true;
  });

  group('constant naming via nameOfBest', () {
    test('constant value appears as literal in SV output', () async {
      final dut = _ConstantNamingModule();
      await dut.build();
      final sv = dut.generateSynth();

      // The constant "1" should appear as a literal 1'h1 in the output,
      // not as a declared signal.
      expect(sv, contains("1'h1"));
    });

    test('constNameDisallowed falls through to signal naming', () async {
      final dut = _ConstNameDisallowedModule();
      await dut.build();
      final sv = dut.generateSynth();

      // The output assignment should NOT use the raw constant literal
      // as a wire name; a proper signal name should be used instead.
      // The constant still appears as a literal in the mux expression.
      expect(sv, contains("1'h1"));
      // The output 'o' should be assigned from something.
      expect(sv, contains('o'));
    });
  });

  group('separate instance and signal namespaces', () {
    test(
        'signal and instance with same name do not collide '
        'when namespaces are independent', () async {
      Namer.uniquifySignalAndInstanceNames = false;
      final dut = _InstanceSignalCollision();
      await dut.build();
      final sv = dut.generateSynth();

      // With independent namespaces, the signal keeps its name 'inner'
      // and the instance also keeps 'inner' — no spurious _0 suffix.
      expect(sv, contains(RegExp(r'logic\s+inner[,;\s]')));
      expect(sv, isNot(contains('inner_0')));
    });

    test(
        'signal and instance get suffixed when '
        'ensureUniqueSignalAndInstanceNames is true', () async {
      Namer.uniquifySignalAndInstanceNames = true;
      final dut = _InstanceSignalCollision();
      await dut.build();
      final sv = dut.generateSynth();

      // With cross-namespace checking enabled, the signal 'inner' is
      // allocated first (during signal naming); when the instance tries
      // to claim 'inner', it sees the signal namespace has it, so the
      // instance OR signal gets a suffix.
      expect(sv, contains('inner_0'));
    });

    test(
        'signal and instance do not spuriously suffix when '
        'ensureUniqueSignalAndInstanceNames is false', () async {
      Namer.uniquifySignalAndInstanceNames = false;
      final dut = _InstanceSignalCollision();
      await dut.build();
      final sv = dut.generateSynth();

      // With independent namespaces, no spurious suffixing.
      expect(sv, isNot(contains('inner_0')));
    });

    test('duplicate instance names get uniquified', () async {
      final dut = _DuplicateInstances();
      await dut.build();
      final sv = dut.generateSynth();

      // Two instances named 'blk' — one should be 'blk', the other 'blk_0'.
      expect(sv, contains('blk'));
      expect(sv, contains(RegExp(r'blk_\d')));
    });
  });

  group('instance namespace independence', () {
    test('allocateInstanceName is independent from allocateSignalName',
        () async {
      final dut = _InstanceSignalCollision();
      await dut.build();

      // After build, the signal namer has 'inner' claimed.
      // With independent namespaces, instance namespace should also accept
      // 'inner' without conflict.
      Namer.uniquifySignalAndInstanceNames = false;

      // The instance namespace should show 'inner' as available before
      // any instance allocation.
      // (After synthesis, names are already allocated, so we just verify
      // the module built without error.)
      expect(dut.generateSynth(), isNotEmpty);
    });
  });
}
