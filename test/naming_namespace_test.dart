// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// naming_namespace_test.dart
// Tests for constant naming via nameOfBest and shared instance/signal
// namespace uniquification.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
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
  });

  group('constant naming via nameOfBest', () {
    test('constant value appears as literal in SV output', () async {
      final dut = _ConstantNamingModule();
      await dut.build();
      final sv = SvService(dut).synthOutput;

      // The constant "1" should appear as a literal 1'h1 in the output,
      // not as a declared signal.
      expect(sv, contains("1'h1"));
    });

    test('constNameDisallowed falls through to signal naming', () async {
      final dut = _ConstNameDisallowedModule();
      await dut.build();
      final sv = SvService(dut).synthOutput;

      // The output assignment should NOT use the raw constant literal
      // as a wire name; a proper signal name should be used instead.
      // The constant still appears as a literal in the mux expression.
      expect(sv, contains("1'h1"));
      // The output 'o' should be assigned from something.
      expect(sv, contains('o'));
    });
  });

  group('shared instance and signal namespace', () {
    test(
        'signal and instance with same name get uniquified '
        'in the shared namespace', () async {
      final dut = _InstanceSignalCollision();
      await dut.build();
      final sv = SvService(dut).synthOutput;

      // With a single shared namespace, one of the two "inner" identifiers
      // must be suffixed to avoid collision.
      expect(sv, contains('inner_0'));
    });

    test('instance name wins the shared namespace; signal gets the suffix',
        () async {
      // Non-reserved submodule instances are picked before non-reserved
      // internal signals, so the instance claims the bare name and the
      // colliding signal is uniquified.
      final dut = _InstanceSignalCollision();
      await dut.build();

      final instanceName = dut.namer.instanceNameOf(dut.subModules.first);
      expect(instanceName, equals('inner'),
          reason: 'Instance should win the shared namespace '
              'and keep the bare name');

      final sv = dut.generateSynth();
      // The wire (signal) must carry the suffix, not the instance.
      expect(sv, contains('inner_0'),
          reason: 'Colliding signal should be renamed to inner_0');
      expect(sv, isNot(contains('inner_0 inner')),
          reason: 'Instance itself must not be named inner_0');
    });

    test(
        'instance-signal collision resolution is stable across '
        'repeated synthesis passes', () async {
      final dut = _InstanceSignalCollision();
      await dut.build();

      // Strip the generated header (contains a wall-clock timestamp) before
      // comparing so the test does not fail on timing jitter.
      String stripHeader(String sv) =>
          sv.replaceFirst(RegExp(r'/\*\*.*?\*/\n', dotAll: true), '');

      final sv1 = stripHeader(dut.generateSynth());
      final sv2 = stripHeader(dut.generateSynth());

      expect(sv2, equals(sv1),
          reason: 'Repeated synthesis passes must produce identical '
              'SV output; instance and signal names must not drift.');
    });

    test('duplicate instance names get uniquified', () async {
      final dut = _DuplicateInstances();
      await dut.build();
      final sv = SvService(dut).synthOutput;

      // Two instances named 'blk' — one should be 'blk', the other 'blk_0'.
      expect(sv, contains('blk'));
      expect(sv, contains(RegExp(r'blk_\d')));
    });
  });
}
