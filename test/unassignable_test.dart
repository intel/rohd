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

  test('Swizzled outputs cannot be assigned', () {
    try {
      [Logic(), Logic()].swizzle() <= Logic(width: 2);
      fail('Should have thrown an exception');
    } on UnassignableException catch (e) {
      expect(e.toString(), contains('Swizzle'));
    }
  });

  test('BusSubset outputs cannot be assigned', () {
    try {
      Logic(width: 2)[0] <= Logic();
      fail('Should have thrown an exception');
    } on UnassignableException catch (e) {
      expect(e.toString(), contains('BusSubset'));
    }
  });
}
