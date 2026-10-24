// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// netlist_evaluator_ops_test.dart
// Tests NetlistEvaluator operations.
//
// 2026 October 22
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd/rohd.dart' show LogicValue;
import 'package:rohd_devtools_extension/rohd_devtools/services/netlist_evaluator.dart';

LogicValue _value(int value, int width) => LogicValue.ofInt(value, width);

void main() {
  group('NetlistEvaluator value helpers', () {
    test('parses hexadecimal and unknown values at the requested width', () {
      expect(parseHexToLV('0x0f', 8), _value(15, 8));
      expect(parseHexToLV("4'hf", 8), _value(15, 8));
      expect(
        parseHexToLV('x', 4),
        LogicValue.filled(4, LogicValue.x),
      );
    });

    test('zero-extends and truncates values to a target width', () {
      expect(matchWidth(_value(3, 2), 4), _value(3, 4));
      expect(matchWidth(_value(0xf, 4), 2), _value(3, 2));
    });
  });

  group('NetlistEvaluator gate operations', () {
    test('evaluates bitwise, mux, reduction, and comparison operations', () {
      expect(
        evalOp('and', [_value(0xc, 4), _value(0xa, 4)], 4, const {}),
        _value(0x8, 4),
      );
      expect(
        evalOp('or', [_value(0xc, 4), _value(0xa, 4)], 4, const {}),
        _value(0xe, 4),
      );
      expect(
        evalOp('xor', [_value(0xc, 4), _value(0xa, 4)], 4, const {}),
        _value(0x6, 4),
      );
      expect(evalOp('not', [_value(0x3, 4)], 4, const {}), _value(0xc, 4));
      expect(evalOp('buf', [_value(0x3, 2)], 4, const {}), _value(0x3, 4));
      expect(
        evalOp(
          'mux',
          [_value(0, 1), _value(0x1, 4), _value(0x2, 4)],
          4,
          const {},
        ),
        _value(0x1, 4),
      );
      expect(
        evalOp(
          'mux',
          [_value(1, 1), _value(0x1, 4), _value(0x2, 4)],
          4,
          const {},
        ),
        _value(0x2, 4),
      );
      expect(
        evalOp('uor', [_value(0x4, 4)], 1, const {}),
        LogicValue.one,
      );
      expect(
        evalOp('uand', [_value(0xf, 4)], 1, const {}),
        LogicValue.one,
      );
      expect(
        evalOp('uxor', [_value(0x3, 4)], 1, const {}),
        LogicValue.zero,
      );
      expect(
        evalOp('eq', [_value(3, 4), _value(3, 2)], 1, const {}),
        LogicValue.one,
      );
      expect(
        evalOp('ne', [_value(3, 4), _value(2, 4)], 1, const {}),
        LogicValue.one,
      );
      expect(
        evalOp('gte', [_value(3, 4), _value(3, 2)], 1, const {}),
        LogicValue.one,
      );
      expect(
        evalOp('lt', [_value(2, 4), _value(3, 4)], 1, const {}),
        LogicValue.one,
      );
      expect(
        evalOp('gt', [_value(3, 4), _value(2, 4)], 1, const {}),
        LogicValue.one,
      );
      expect(
        evalOp('le', [_value(2, 4), _value(2, 4)], 1, const {}),
        LogicValue.one,
      );
    });

    test('evaluates arithmetic, shifts, logical, bus, and swizzle operations',
        () {
      expect(
        evalOp('add', [_value(3, 4), _value(2, 4)], 4, const {}),
        _value(5, 4),
      );
      expect(
        evalOp('sub', [_value(5, 4), _value(2, 4)], 4, const {}),
        _value(3, 4),
      );
      expect(
        evalOp('mul', [_value(3, 4), _value(2, 4)], 4, const {}),
        _value(6, 4),
      );
      expect(evalOp('neg', [_value(1, 4)], 4, const {}), _value(15, 4));
      expect(
        evalOp('sll', [_value(3, 4), _value(1, 2)], 4, const {}),
        _value(6, 4),
      );
      expect(
        evalOp('srl', [_value(6, 4), _value(1, 2)], 4, const {}),
        _value(3, 4),
      );
      expect(
        evalOp('ssrl', [_value(6, 4), _value(1, 2)], 4, const {}),
        _value(3, 4),
      );
      expect(
        evalOp('lnot', [_value(0, 4)], 1, const {}),
        LogicValue.one,
      );
      expect(
        evalOp('land', [_value(1, 1), _value(2, 2)], 1, const {}),
        LogicValue.one,
      );
      expect(
        evalOp('lor', [_value(0, 1), _value(2, 2)], 1, const {}),
        LogicValue.one,
      );
      expect(
        evalOp(
          'bus',
          [_value(22, 5)],
          3,
          const {'lo': 1, 'hi': 3},
        ),
        _value(3, 3),
      );
      expect(
        evalOp(
          'bus',
          [_value(22, 5)],
          3,
          const {'lo': 1, 'hi': 3, 'rev': true},
        ),
        _value(6, 3),
      );
      expect(
        evalOp(
          'swz',
          [_value(1, 2), _value(2, 2)],
          4,
          const {
            'iw': [2, 2]
          },
        ),
        _value(9, 4),
      );
    });

    test('returns unknown values for invalid or unsupported operations', () {
      final unknown = LogicValue.filled(4, LogicValue.x);
      expect(evalOp('and', [_value(1, 4)], 4, const {}), unknown);
      expect(evalOp('mux', [_value(1, 1)], 4, const {}), unknown);
      expect(
        evalOp(
          'mux',
          [
            LogicValue.filled(1, LogicValue.x),
            _value(1, 4),
            _value(2, 4),
          ],
          4,
          const {},
        ),
        unknown,
      );
      expect(
        evalOp('eq', [LogicValue.filled(4, LogicValue.x), _value(1, 4)], 1,
            const {}),
        LogicValue.filled(1, LogicValue.x),
      );
      expect(
        evalOp('sll', [_value(1, 4), LogicValue.filled(1, LogicValue.x)], 4,
            const {}),
        unknown,
      );
      expect(evalOp('bus', const [], 4, const {}), unknown);
      expect(
        evalOp(
            'swz',
            [_value(1, 2)],
            4,
            const {
              'iw': [2, 2]
            }),
        unknown,
      );
      expect(evalOp('unknown', const [], 4, const {}), unknown);
    });
  });
}
