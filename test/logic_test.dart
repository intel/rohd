// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_test.dart
// Unit tests for `Logic` functionality.
//
// 2025 July 24
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {
  test('packed simple logic returns itself', () {
    final logic = Logic();
    expect(logic.packed, logic);
  });
}
