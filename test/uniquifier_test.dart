// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// uniquifier_test.dart
// Tests for the Uniquifier
//
// 2023 November 3
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/uniquifier.dart';
import 'package:test/test.dart';

void main() {
  test('Using same reserved name twice throws', () {
    final uniq = Uniquifier(reservedNames: {'apple'})
      ..getUniqueName(initialName: 'apple', reserved: true);

    expect(() => uniq.getUniqueName(initialName: 'apple', reserved: true),
        throwsA(isA<UnavailableReservedNameException>()));
  });
}
