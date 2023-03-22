// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// timestamper_test.dart
// Tests for Timestamper.
//
// 2023 February 18
// Author: Chykon

import 'package:rohd/src/utilities/timestamper.dart';
import 'package:test/test.dart';

void main() {
  group('Timestamper', () {
    test('format must be correct', () {
      final regexp = RegExp(
          r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} [+-]\d{2}:\d{2}$');

      final timestamp = Timestamper.stamp();

      expect(regexp.hasMatch(timestamp), equals(true));
    });
  });
}
