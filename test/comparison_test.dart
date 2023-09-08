// Copyright (C) 2021-2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// comparison_test.dart
// Unit tests for comparison operations
//
// 2021 May 21
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class ComparisonTestModule extends Module {
  final int c;
  ComparisonTestModule(Logic a, Logic b, {this.c = 5})
      : super(name: 'gatetestmodule') {
    if (a.width != b.width) {
      throw Exception('a and b must be same width, but found $a and $b.');
    }
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);

    final aEqB = addOutput('a_eq_b');
    final aNeqB = addOutput('a_neq_b');
    final aLtB = addOutput('a_lt_b');
    final aLteB = addOutput('a_lte_b');
    final aGtB = addOutput('a_gt_b');
    final aGteB = addOutput('a_gte_b');
    final aGtOperatorB = addOutput('a_gt_operator_b');
    final aGteOperatorB = addOutput('a_gte_operator_b');

    final aEqC = addOutput('a_eq_c');
    final aNeqC = addOutput('a_neq_c');
    final aLtC = addOutput('a_lt_c');
    final aLteC = addOutput('a_lte_c');
    final aGtC = addOutput('a_gt_c');
    final aGteC = addOutput('a_gte_c');
    final aGtOperatorC = addOutput('a_gt_operator_c');
    final aGteOperatorC = addOutput('a_gte_operator_c');

    aEqB <= a.eq(b);
    aNeqB <= a.neq(b);
    aLtB <= a.lt(b);
    aLteB <= a.lte(b);
    aGtB <= a.gt(b);
    aGteB <= a.gte(b);
    aGtOperatorB <= (a > b);
    aGteOperatorB <= (a >= b);

    aEqC <= a.eq(c);
    aNeqC <= a.neq(c);
    aLtC <= a.lt(c);
    aLteC <= a.lte(c);
    aGtC <= a.gt(c);
    aGteC <= a.gte(c);
    aGtOperatorC <= (a > c);
    aGteOperatorC <= (a >= c);
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('simcompare', () {
    test('compares', () async {
      final gtm = ComparisonTestModule(Logic(width: 8), Logic(width: 8));
      await gtm.build();
      final vectors = [
        Vector({
          'a': 0,
          'b': 0
        }, {
          'a_eq_b': 1,
          'a_neq_b': 0,
          'a_lt_b': 0,
          'a_lte_b': 1,
          'a_gt_b': 0,
          'a_gte_b': 1,
          'a_gt_operator_b': 0,
          'a_gte_operator_b': 1,
          'a_eq_c': 0,
          'a_neq_c': 1,
          'a_lt_c': 1,
          'a_lte_c': 1,
          'a_gt_c': 0,
          'a_gte_c': 0,
          'a_gt_operator_c': 0,
          'a_gte_operator_c': 0,
        }),
        Vector({
          'a': 5,
          'b': 6
        }, {
          'a_eq_b': 0,
          'a_neq_b': 1,
          'a_lt_b': 1,
          'a_lte_b': 1,
          'a_gt_b': 0,
          'a_gte_b': 0,
          'a_gt_operator_b': 0,
          'a_gte_operator_b': 0,
          'a_eq_c': 1,
          'a_neq_c': 0,
          'a_lt_c': 0,
          'a_lte_c': 1,
          'a_gt_c': 0,
          'a_gte_c': 1,
          'a_gt_operator_c': 0,
          'a_gte_operator_c': 1,
        }),
        Vector({
          'a': 9,
          'b': 7
        }, {
          'a_eq_b': 0,
          'a_neq_b': 1,
          'a_lt_b': 0,
          'a_lte_b': 0,
          'a_gt_b': 1,
          'a_gte_b': 1,
          'a_gt_operator_b': 1,
          'a_gte_operator_b': 1,
          'a_eq_c': 0,
          'a_neq_c': 1,
          'a_lt_c': 0,
          'a_lte_c': 0,
          'a_gt_c': 1,
          'a_gte_c': 1,
          'a_gt_operator_c': 1,
          'a_gte_operator_c': 1,
        }),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(gtm, vectors);
      expect(simResult, equals(true));
    });
  });
}
