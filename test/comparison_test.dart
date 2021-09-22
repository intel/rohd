/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
/// 
/// comparison_test.dart
/// Unit tests for comparison operations
/// 
/// 2021 May 21
/// Author: Max Korbel <max.korbel@intel.com>
/// 

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';
import 'package:rohd/src/utilities/simcompare.dart';

class ComparisonTestModule extends Module {

  final int c;
  ComparisonTestModule(Logic a, Logic b, {this.c = 5}) : super(name: 'gatetestmodule') {
    if(a.width != b.width) throw Exception('a and b must be same width');
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);

    var aEqB = addOutput('a_eq_b');
    var aLtB = addOutput('a_lt_b');
    var aLteB = addOutput('a_lte_b');
    var aGtB = addOutput('a_gt_b');
    var aGteB = addOutput('a_gte_b');

    var aEqC = addOutput('a_eq_c');
    var aLtC = addOutput('a_lt_c');
    var aLteC = addOutput('a_lte_c');
    var aGtC = addOutput('a_gt_c');
    var aGteC = addOutput('a_gte_c');

    aEqB <= a.eq(b);
    aLtB <= a.lt(b);
    aLteB <= a.lte(b);
    aGtB <= (a > b);
    aGteB <= (a >= b);

    aEqC <= a.eq(c);
    aLtC <= a.lt(c);
    aLteC <= a.lte(c);
    aGtC <= (a > c);
    aGteC <= (a >= c);
  }

}


void main() {
  tearDown(() {
    Simulator.reset();
  });

  
  group('simcompare', () {
    var signalToWidthMap = {
      'a':8,
      'b':8,
  };

    //TODO: test (and finish implementing) negatives extensively (twos complement) with comparisons

    test('compares', () async {
      var gtm = ComparisonTestModule(Logic(width: 8), Logic(width:8));
      await gtm.build();
      var vectors = [
        Vector({'a': 0, 'b': 0}, {
          'a_eq_b':  1,
          'a_lt_b':  0,
          'a_lte_b': 1,
          'a_gt_b':  0,
          'a_gte_b': 1,
          'a_eq_c':  0,
          'a_lt_c':  1,
          'a_lte_c': 1,
          'a_gt_c':  0,
          'a_gte_c': 0,
        }),
        Vector({'a': 5, 'b': 6}, {
          'a_eq_b':  0,
          'a_lt_b':  1,
          'a_lte_b': 1,
          'a_gt_b':  0,
          'a_gte_b': 0,
          'a_eq_c':  1,
          'a_lt_c':  0,
          'a_lte_c': 1,
          'a_gt_c':  0,
          'a_gte_c': 1,
        }),
        Vector({'a': 9, 'b': 7}, {
          'a_eq_b':  0,
          'a_lt_b':  0,
          'a_lte_b': 0,
          'a_gt_b':  1,
          'a_gte_b': 1,
          'a_eq_c':  0,
          'a_lt_c':  0,
          'a_lte_c': 0,
          'a_gt_c':  1,
          'a_gte_c': 1,
        }),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      var simResult = SimCompare.iverilogVector(gtm.generateSynth(), gtm.runtimeType.toString(), vectors, 
        signalToWidthMap: signalToWidthMap
      );
      expect(simResult, equals(true));
    });

  });
}