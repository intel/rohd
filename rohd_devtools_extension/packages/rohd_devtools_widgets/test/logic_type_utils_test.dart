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

  group('formatFieldValue', () {
    test('formats short binary, long hex, and unknown values', () {
      expect(formatFieldValue(null, 4), isEmpty);
      expect(formatFieldValue('', 4), isEmpty);
      expect(formatFieldValue('1010', 4), "4'b1010");
      expect(formatFieldValue('00011010', 8), "8'h1a");
      expect(formatFieldValue('10x0', 4), "4'hx");
      expect(formatFieldValue('10z0', 4), "4'hz");
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

  test('expandLogicType normalizes absolute struct bits and nested fields', () {
    final nodes = expandLogicType(
      {
        'typeName': 'Packet',
        'fields': [
          {
            'name': 'payload',
            'width': 4,
            'bits': [100, 101, 102, 103],
            'type': {
              'fields': [
                {
                  'name': 'low',
                  'width': 2,
                  'bits': [0, 1],
                },
                {
                  'name': 'high',
                  'width': 2,
                  'bits': [2, 3],
                },
              ],
            },
          },
          {
            'name': 'valid',
            'width': 1,
            'bits': [104],
          },
        ],
      },
      parentBinaryValue: '11010',
    );

    expect(nodes, hasLength(2));
    expect(nodes[0].name, 'payload');
    expect(nodes[0].startBit, 0);
    expect(nodes[0].value, '1010');
    expect(nodes[0].children, hasLength(2));
    expect(nodes[0].children[0].value, '10');
    expect(nodes[0].children[1].value, '10');
    expect(nodes[1].name, 'valid');
    expect(nodes[1].startBit, 4);
    expect(nodes[1].value, '1');
  });

  test('expandLogicType expands multidimensional arrays', () {
    final nodes = expandLogicType(
      {
        'arrayDims': [2, 2],
        'elementWidth': 2,
      },
      parentBinaryValue: '11100100',
    );

    expect(nodes, hasLength(2));
    expect(nodes[0].name, '[0]');
    expect(nodes[0].width, 4);
    expect(nodes[0].value, '0100');
    expect(nodes[0].children.map((child) => child.value), ['00', '01']);
    expect(nodes[1].value, '1110');
    expect(nodes[1].children.map((child) => child.value), ['10', '11']);
  });

  test('formatTypeTooltip includes signal name, type, values, and depth limit',
      () {
    final tooltip = formatTypeTooltip(
      {
        'typeName': 'Packet',
        'fields': [
          {
            'name': 'payload',
            'width': 4,
            'bits': [0, 1, 2, 3],
            'type': {
              'fields': [
                {
                  'name': 'nibble',
                  'width': 4,
                  'bits': [0, 1, 2, 3],
                  'type': {
                    'fields': [
                      {
                        'name': 'bit0',
                        'width': 1,
                        'bits': [0],
                      },
                    ],
                  },
                },
              ],
            },
          },
        ],
      },
      parentBinaryValue: '1010',
      signalName: 'packet',
      maxDepth: 2,
    );

    expect(
      tooltip,
      '''packet (Packet)
  payload: 4'b1010
    nibble: 4'b1010
      ...''',
    );
  });
}
