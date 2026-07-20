// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// leaf_test_module_factories.dart
// Shared representative leaf modules for synthesis contract tests.
//
// 2026 July
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';

/// Representative inline leaf modules for focused contract tests.
List<InlineSystemVerilog> representativeInlineLeafModules() => [
      NotGate(Logic(name: 'n', width: 3)),
      And2Gate(Logic(name: 'a', width: 4), Logic(name: 'b', width: 4)),
      LShift(Logic(name: 'lhs', width: 9), Logic(name: 'sh', width: 4)),
      Mux(
        Logic(name: 'sel'),
        Logic(name: 'd1', width: 4),
        Logic(name: 'd0', width: 4),
      ),
      BusSubset(Logic(name: 'bus', width: 12), 9, 4),
      ReplicationOp(Logic(name: 'in', width: 3), 4),
      IndexGate(Logic(name: 'word', width: 8), Logic(name: 'idx', width: 3)),
      Swizzle([
        Logic(name: 's0', width: 2),
        Logic(name: 's1'),
        Logic(name: 's2', width: 3),
      ]),
    ];

/// All known built-in inline leaf modules expected to have inference coverage.
List<InlineSystemVerilog> allKnownInlineLeafModules() => [
      NotGate(Logic(name: 'n', width: 3)),
      And2Gate(Logic(name: 'a', width: 4), Logic(name: 'b', width: 4)),
      Or2Gate(Logic(name: 'a', width: 4), Logic(name: 'b', width: 4)),
      Xor2Gate(Logic(name: 'a', width: 4), Logic(name: 'b', width: 4)),
      Subtract(Logic(name: 'a', width: 5), Logic(name: 'b', width: 5)),
      Multiply(Logic(name: 'a', width: 5), Logic(name: 'b', width: 5)),
      Divide(Logic(name: 'a', width: 5), Logic(name: 'b', width: 5)),
      Modulo(Logic(name: 'a', width: 5), Logic(name: 'b', width: 5)),
      Power(Logic(name: 'a', width: 5), Logic(name: 'b', width: 5)),
      Equals(Logic(name: 'a', width: 4), Logic(name: 'b', width: 4)),
      NotEquals(Logic(name: 'a', width: 4), Logic(name: 'b', width: 4)),
      LessThan(Logic(name: 'a', width: 4), Logic(name: 'b', width: 4)),
      GreaterThan(Logic(name: 'a', width: 4), Logic(name: 'b', width: 4)),
      LessThanOrEqual(Logic(name: 'a', width: 4), Logic(name: 'b', width: 4)),
      GreaterThanOrEqual(
          Logic(name: 'a', width: 4), Logic(name: 'b', width: 4)),
      AndUnary(Logic(name: 'u', width: 6)),
      OrUnary(Logic(name: 'u', width: 6)),
      XorUnary(Logic(name: 'u', width: 6)),
      LShift(Logic(name: 'lhs', width: 9), Logic(name: 'sh', width: 4)),
      RShift(Logic(name: 'lhs', width: 9), Logic(name: 'sh', width: 4)),
      ARShift(Logic(name: 'lhs', width: 9), Logic(name: 'sh', width: 4)),
      Mux(
        Logic(name: 'sel'),
        Logic(name: 'd1', width: 4),
        Logic(name: 'd0', width: 4),
      ),
      IndexGate(Logic(name: 'word', width: 8), Logic(name: 'idx', width: 3)),
      BusSubset(Logic(name: 'bus', width: 12), 9, 4),
      Swizzle([
        Logic(name: 's0', width: 2),
        Logic(name: 's1'),
        Logic(name: 's2', width: 3),
      ]),
      ReplicationOp(Logic(name: 'in', width: 3), 4),
    ];
