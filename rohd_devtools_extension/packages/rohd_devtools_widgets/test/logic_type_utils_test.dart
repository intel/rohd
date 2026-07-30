// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_type_utils_test.dart
// Tests for LogicStructure/LogicArray type expansion utilities.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';

void main() {
  group('hexToBinary', () {
    test('converts hex values through LogicValue radix parsing', () {
      expect(hexToBinary('0x1a', 8), '00011010');
      expect(hexToBinary('1a', 4), '1010');
      expect(hexToBinary('x', 3), 'xxx');
      expect(hexToBinary('z', 5), '0zzzz');
    });

    test('returns null for invalid hex input', () {
      expect(hexToBinary('g', 4), isNull);
    });
  });

  test('expandLogicType slices contiguous array elements with LogicValue', () {
    final nodes = expandLogicType(
      {
        'arrayDims': [2],
        'elementWidth': 4,
      },
      parentBinaryValue: '10101100',
    );

    expect(nodes, hasLength(2));
    expect(nodes[0].value, '1100');
    expect(nodes[1].value, '1010');
  });
}
