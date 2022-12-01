/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// assignment_test.dart
/// Unit tests for assignment-specific issues.
///
/// 2022 September 19
/// Author: Max Korbel <max.korbel@intel.com>
///
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class ExampleModule extends Module {
  ExampleModule() {
    final out = addOutput('out');
    final val = Logic(name: 'val');
    val <= Const(1);

    Combinational([
      out < val,
    ]);
  }

  Logic get out => output('out');
}

void main() {
  // From https://github.com/intel/rohd/issues/159
  // Thank you to @chykon for reporting!
  test('const comb assignment', () async {
    final exampleModule = ExampleModule();
    await exampleModule.build();

    final vectors = [
      Vector({}, {'out': 1}),
    ];
    await SimCompare.checkFunctionalVector(exampleModule, vectors);
    final simResult = SimCompare.iverilogVector(
      exampleModule,
      vectors,
      allowWarnings: true, // since always_comb has no sensitivities
    );
    expect(simResult, equals(true));
  });
}
