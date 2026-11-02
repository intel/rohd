// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// unassignable_test.dart
// Tests for unassignable cases
//
// 2024 October 24
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {
  test('Const cannot be assigned', () {
    try {
      Const(1) <= Logic();
      fail('Should have thrown an exception');
    } on UnassignableException catch (e) {
      expect(e.toString(), contains('Const'));
    }
  });

  test('Swizzled outputs reject width mismatches', () {
    expect(
      () => [Logic(), Logic()].swizzle() <= Logic(),
      throwsA(isA<SignalWidthMismatchException>()),
    );
  });

  test('BusSubset outputs reject width mismatches', () {
    expect(
      () => Logic(width: 2)[0] <= Logic(width: 2),
      throwsA(isA<SignalWidthMismatchException>()),
    );
  });

  test('Swizzled outputs cannot receive conditional assignments', () {
    expect(
      () => Swizzle([Logic(), Logic()]).out < Logic(width: 2),
      throwsA(isA<UnassignableException>()),
    );
  });

  test('BusSubset outputs cannot receive conditional assignments', () {
    expect(
      () => Logic(width: 2)[0] < Logic(),
      throwsA(isA<UnassignableException>()),
    );
  });

  test('SimpleClockGenerator outputs cannot be assigned', () {
    try {
      SimpleClockGenerator(2).clk <= Logic();
      fail('Should have thrown an exception');
    } on UnassignableException catch (e) {
      expect(e.toString(), contains('SimpleClockGenerator'));
    }
  });

  group('gates', () {
    for (final out in [
      Logic() & Logic(), // 2 input
      ~Logic(), // not
      Logic(width: 2).or(), // unary
      Logic().replicate(3), // replication
      Logic(width: 3) > Logic(width: 3), // comparison
      Logic(width: 3) << 2, // shift
      mux(Logic(), Logic(), Logic()), // mux
      Logic(width: 2)[Logic()] // index
    ]) {
      test('${out.parentModule.runtimeType} outputs cannot be assigned', () {
        try {
          out <= Logic();
          fail('Should have thrown an exception');
        } on UnassignableException catch (e) {
          expect(e.toString(), contains(out.parentModule!.definitionName));
        }
      });
    }
  });
}
