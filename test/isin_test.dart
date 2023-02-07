/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// isin_test.dart
/// Unit tests for Logic.IsIn() operations
///
/// 2023 February 7
/// Author: Rahul Gautham Putcha <rahul.gautham.putcha@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class LogicIsInModule extends Module {
  // --- getter for Logic IsIn List
  Logic get logicIsIn => output('a_is_in');

  LogicIsInModule(Logic a, List<Logic> list)
      : super(name: 'logicisintestmodule') {
    a = addInput('a', a, width: a.width);

    var i = 0;
    final inputList = <Logic>[];
    for (final ele in list) {
      inputList.add(addInput('list_element_$i', ele, width: ele.width));
      i++;
    }
    final logicIsIn = addOutput('a_is_in');
    logicIsIn <= a.isIn(inputList);
  }
}

class LogicIsInIntModule extends Module {
  // --- getter for Logic IsIn List
  Logic get logicIsIn => output('a_is_in');

  LogicIsInIntModule(Logic a, List<int> list)
      : super(name: 'logicisintestmodule') {
    a = addInput('a', a, width: a.width);
    final logicIsIn = addOutput('a_is_in');
    logicIsIn <= a.isIn(list);
  }
}

class LogicIsInMixModule extends Module {
  // --- getter for Logic IsIn List
  Logic get logicIsIn => output('a_is_in');

  LogicIsInMixModule(Logic a, List<dynamic> list)
      : super(name: 'logicisintestmodule') {
    a = addInput('a', a, width: a.width);

    var i = 0;
    final inputList = <dynamic>[];
    for (final ele in list) {
      if (ele is Logic) {
        inputList.add(addInput('list_element_$i', ele, width: ele.width));
        i++;
      } else {
        inputList.add(ele);
      }
    }

    final logicIsIn = addOutput('a_is_in');
    logicIsIn <= a.isIn(inputList);
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('functional', () {
    test('Logic isIn', () async {
      final gtm = LogicIsInModule(
          Logic(width: 8), <Logic>[Logic(width: 8), Logic(width: 8)]);
      await gtm.build();
      final vectors = [
        Vector(
            {'a': 5, 'list_element_0': 1, 'list_element_1': 5}, {'a_is_in': 1}),
        Vector(
            {'a': 5, 'list_element_0': 1, 'list_element_1': 2}, {'a_is_in': 0})
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(gtm, vectors);
      expect(simResult, equals(true));
    });

    test('Logic isIn in Int list', () async {
      // Testcase 1
      final gtm = LogicIsInIntModule(Logic(width: 8), <int>[5, 11]);
      await gtm.build();
      final vectors = [
        Vector({'a': 5}, {'a_is_in': 1}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(gtm, vectors);
      expect(simResult, equals(true));
    });

    test('Logic `Not` isIn Int list', () async {
      // Testcase 1
      final gtm = LogicIsInIntModule(Logic(width: 8), <int>[5, 11]);
      await gtm.build();
      final vectors = [
        Vector({'a': 1}, {'a_is_in': 0}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(gtm, vectors);
      expect(simResult, equals(true));
    });

    test('Logic isIn Mixed list', () async {
      // Testcase 1
      final gtm = LogicIsInMixModule(
          Logic(width: 8), <dynamic>[Logic(width: 8), 5, 11, Logic(width: 8)]);
      await gtm.build();
      final vectors = [
        Vector(
            {'a': 6, 'list_element_0': 2, 'list_element_1': 6}, {'a_is_in': 1}),
        Vector(
            {'a': 5, 'list_element_0': 2, 'list_element_1': 6}, {'a_is_in': 1}),
        Vector(
            {'a': 1, 'list_element_0': 2, 'list_element_1': 6}, {'a_is_in': 0}),
        Vector(
            {'a': 6, 'list_element_0': 1, 'list_element_1': 2}, {'a_is_in': 0}),
      ];
      await SimCompare.checkFunctionalVector(gtm, vectors);
      final simResult = SimCompare.iverilogVector(gtm, vectors);
      expect(simResult, equals(true));
    });
  });
}
